import {NextResponse} from 'next/server';import {stripeReady,stripeRequest} from '../../../../lib/stripeServer';
export const runtime='nodejs';
export async function GET(){try{
 if(!stripeReady())return NextResponse.json({configured:false});
 const [balance,payouts,sessions,transactions]=await Promise.all([
   stripeRequest('/balance'),
   stripeRequest('/payouts?limit=10'),
   stripeRequest('/checkout/sessions?limit=50&status=complete&expand[]=data.line_items&expand[]=data.payment_intent.latest_charge.balance_transaction'),
   stripeRequest('/balance_transactions?limit=100&type=charge')
 ]);
 const orders=(sessions.data||[]).map(s=>{
   const pi=typeof s.payment_intent==='object'?s.payment_intent:null;
   const charge=pi&&typeof pi.latest_charge==='object'?pi.latest_charge:null;
   const bt=charge&&typeof charge.balance_transaction==='object'?charge.balance_transaction:null;
   return{
    id:s.id,
    created:s.created,
    amount_total:s.amount_total||0,
    currency:s.currency||'usd',
    payment_status:s.payment_status||'unknown',
    customer_email:s.customer_details?.email||s.customer_email||'',
    customer_name:s.customer_details?.name||'',
    fulfillment_status:s.metadata?.fulfillment_status||'new',
    payment_intent:pi?.id||(typeof s.payment_intent==='string'?s.payment_intent:''),
    charge_id:charge?.id||'',
    refunded:Boolean(charge?.refunded),
    amount_refunded:charge?.amount_refunded||0,
    fee:bt?.fee||0,
    net:bt?.net??null,
    items:(s.line_items?.data||[]).map(li=>({name:li.description||'Store item',quantity:li.quantity||1,amount_total:li.amount_total||0}))
   }
 });
 const tx=transactions.data||[];
 const metrics={
   gross:tx.reduce((n,t)=>n+(t.amount||0),0),
   fees:tx.reduce((n,t)=>n+(t.fee||0),0),
   net:tx.reduce((n,t)=>n+(t.net||0),0),
   refunds:orders.reduce((n,o)=>n+(o.amount_refunded||0),0),
   orders:orders.length
 };
 return NextResponse.json({configured:true,balance,payouts:payouts.data||[],orders,metrics});
}catch(e){return NextResponse.json({error:e.message},{status:500})}}
