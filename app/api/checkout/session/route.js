import {NextResponse} from 'next/server';import {stripeReady,stripeRequest} from '../../../../lib/stripeServer';import {getProduct} from '../../../../lib/products';
export const runtime='nodejs';
export async function GET(req){try{
 if(!stripeReady())return NextResponse.json({error:'Checkout is not configured.'},{status:503});
 const id=new URL(req.url).searchParams.get('session_id')||'';
 if(!/^cs_[A-Za-z0-9_]+$/.test(id))return NextResponse.json({error:'Invalid checkout session.'},{status:400});
 const s=await stripeRequest('/checkout/sessions/'+encodeURIComponent(id)+'?expand[]=line_items');
 const items=[];
 for(let i=0;i<20;i++){
   const raw=s.metadata?.['item_'+i];
   if(!raw)continue;
   const idx=raw.lastIndexOf(':');
   const slug=idx>-1?raw.slice(0,idx):raw;
   const qty=idx>-1?Math.max(1,Number(raw.slice(idx+1))||1):1;
   const p=getProduct(slug);
   if(p)items.push({slug:p.slug,title:p.title,qty,delivery:p.delivery,category:p.category});
 }
 if(!items.length)for(const li of s.line_items?.data||[])items.push({slug:'',title:li.description||'Store item',qty:li.quantity||1,delivery:'Contact purchase support if fulfillment is required.',category:'STORE'});
 return NextResponse.json({
   id:s.id,
   paid:s.payment_status==='paid',
   payment_status:s.payment_status,
   amount_total:s.amount_total||0,
   currency:s.currency||'usd',
   email:s.customer_details?.email||s.customer_email||'',
   name:s.customer_details?.name||'',
   created:s.created,
   receipt_email:s.customer_details?.email||s.customer_email||'',
   items
 });
}catch(e){return NextResponse.json({error:e.message||'Unable to load order.'},{status:400})}}
