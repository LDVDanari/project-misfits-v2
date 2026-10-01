import {NextResponse} from 'next/server';import {stripeReady,stripeRequest} from '../../../../lib/stripeServer';
export const runtime='nodejs';
export async function POST(req){try{
 if(req.headers.get('x-pmv2-owner-action')!=='refund')return NextResponse.json({error:'Invalid owner action.'},{status:403});
 if(!stripeReady())return NextResponse.json({error:'Stripe is not configured.'},{status:503});
 const {payment_intent,order_id}=await req.json();
 if(!/^pi_[A-Za-z0-9_]+$/.test(String(payment_intent||'')))return NextResponse.json({error:'Missing valid payment reference.'},{status:400});
 const refund=await stripeRequest('/refunds',{method:'POST',body:{payment_intent:String(payment_intent),reason:'requested_by_customer','metadata[order_id]':String(order_id||'')}});
 if(order_id&&/^cs_[A-Za-z0-9_]+$/.test(String(order_id))){
   try{await stripeRequest('/checkout/sessions/'+encodeURIComponent(order_id),{method:'POST',body:{'metadata[fulfillment_status]':'refunded'}})}catch{}
 }
 return NextResponse.json({ok:true,refund});
}catch(e){return NextResponse.json({error:e.message||'Refund failed.'},{status:400})}}
