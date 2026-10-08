import {NextResponse} from 'next/server';import {stripeReady,stripeRequest} from '../../../../lib/stripeServer';import {dbReady} from '../../../../lib/db';import {markOrderFulfilled} from '../../../../lib/fulfillment';
export const runtime='nodejs';
const allowed=new Set(['new','processing','fulfilled']);
export async function POST(req){try{
 if(req.headers.get('x-pmv2-owner-action')!=='order-status')return NextResponse.json({error:'Invalid owner action.'},{status:403});
 if(!stripeReady())return NextResponse.json({error:'Stripe is not configured.'},{status:503});
 const {session_id,status}=await req.json();
 if(!/^cs_[A-Za-z0-9_]+$/.test(String(session_id||''))||!allowed.has(status))return NextResponse.json({error:'Invalid order update.'},{status:400});
 const session=await stripeRequest('/checkout/sessions/'+encodeURIComponent(session_id),{method:'POST',body:{'metadata[fulfillment_status]':status}});
 if(status==='fulfilled'&&dbReady()){try{await markOrderFulfilled(session_id,'owner')}catch(e){console.error('PMv2 could not mark order fulfilled in database:',e.message)}}
 return NextResponse.json({ok:true,status:session.metadata?.fulfillment_status||status});
}catch(e){return NextResponse.json({error:e.message||'Unable to update order.'},{status:400})}}
