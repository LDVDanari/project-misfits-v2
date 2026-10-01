import {NextResponse} from 'next/server';import {priceToCents,stripeRequest,stripeReady} from '../../../lib/stripeServer';import {getResolvedCatalog} from '../../../lib/catalogServer';
export const runtime='nodejs';
function publicOrigin(req){
  const env=(process.env.NEXT_PUBLIC_SITE_URL||'').trim().replace(/\/$/,'');
  if(env&&/^https?:\/\//i.test(env)&&!env.includes('0.0.0.0')&&!env.includes('127.0.0.1')&&!env.includes('localhost'))return env;
  const proto=(req.headers.get('x-forwarded-proto')||'https').split(',')[0].trim();
  const host=(req.headers.get('x-forwarded-host')||req.headers.get('host')||'').split(',')[0].trim();
  if(host&&!host.startsWith('0.0.0.0')&&!host.startsWith('127.0.0.1')&&!host.startsWith('localhost'))return proto+'://'+host;
  return 'https://projectmisfitsrp.com';
}
export async function POST(req){try{
  if(!stripeReady())return NextResponse.json({error:'Checkout is not configured yet.'},{status:503});
  const {items}=await req.json();
  const catalog=await getResolvedCatalog();
  if(!Array.isArray(items)||!items.length)return NextResponse.json({error:'Cart is empty.'},{status:400});
  const rows=items.map(row=>{
    const product=catalog.find(p=>p.slug===row.slug);
    if(!product||!product.active||product.price==='COMING SOON')throw new Error('One or more store items are unavailable.');
    const qty=Math.max(1,Math.min(10,Number(row.qty)||1));
    return{product,qty,unit_amount:priceToCents(product.price)};
  });
  const origin=publicOrigin(req);
  let taxCode=process.env.STRIPE_TAX_CODE||'';
  if(!taxCode){try{const taxSettings=await stripeRequest('/tax/settings');taxCode=taxSettings?.defaults?.tax_code||'';}catch{}}
  if(!taxCode)return NextResponse.json({error:'Stripe tax code is not configured. Set a default tax code in Stripe Tax settings or STRIPE_TAX_CODE in Coolify.'},{status:503});
  const body={mode:'payment',success_url:origin+'/checkout/success?session_id={CHECKOUT_SESSION_ID}',cancel_url:origin+'/checkout?canceled=1',allow_promotion_codes:'true'};
  rows.forEach((r,i)=>{body[`line_items[${i}][price_data][currency]`]='usd';body[`line_items[${i}][price_data][unit_amount]`]=String(r.unit_amount);body[`line_items[${i}][price_data][product_data][name]`]=r.product.title;body[`line_items[${i}][price_data][product_data][description]`]=r.product.short||'Project Misfits v2 store purchase';body[`line_items[${i}][price_data][product_data][tax_code]`]=taxCode;body[`line_items[${i}][quantity]`]=String(r.qty);body[`metadata[item_${i}]`]=r.product.slug+':'+r.qty});
  const session=await stripeRequest('/checkout/sessions',{method:'POST',body});
  return NextResponse.json({url:session.url});
}catch(e){return NextResponse.json({error:e.message||'Unable to start checkout.'},{status:400})}}
