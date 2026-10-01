import {NextResponse} from 'next/server';import {stripeReady,stripeRequest} from '../../../../lib/stripeServer';
export const runtime='nodejs';
export async function GET(){try{
 if(!stripeReady())return NextResponse.json({configured:false});
 const [balance,payouts,sessions]=await Promise.all([
   stripeRequest('/balance'),
   stripeRequest('/payouts?limit=10'),
   stripeRequest('/checkout/sessions?limit=20&status=complete&expand[]=data.line_items')
 ]);
 const orders=(sessions.data||[]).map(s=>({
   id:s.id,
   created:s.created,
   amount_total:s.amount_total||0,
   currency:s.currency||'usd',
   payment_status:s.payment_status||'unknown',
   customer_email:s.customer_details?.email||s.customer_email||'',
   customer_name:s.customer_details?.name||'',
   fulfillment_status:s.metadata?.fulfillment_status||'new',
   items:(s.line_items?.data||[]).map(li=>({name:li.description||'Store item',quantity:li.quantity||1,amount_total:li.amount_total||0}))
 }));
 return NextResponse.json({configured:true,balance,payouts:payouts.data||[],orders});
}catch(e){return NextResponse.json({error:e.message},{status:500})}}
