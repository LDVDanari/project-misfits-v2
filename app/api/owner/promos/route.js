import {NextResponse} from 'next/server';import {stripeReady,stripeRequest} from '../../../../lib/stripeServer';
export const runtime='nodejs';
export async function GET(){try{
 if(!stripeReady())return NextResponse.json({configured:false});
 const r=await stripeRequest('/promotion_codes?limit=50');
 return NextResponse.json({configured:true,codes:(r.data||[]).map(x=>({id:x.id,code:x.code,active:x.active,coupon:typeof x.coupon==='object'?{id:x.coupon.id,percent_off:x.coupon.percent_off,amount_off:x.coupon.amount_off,currency:x.coupon.currency}:null,max_redemptions:x.max_redemptions,times_redeemed:x.times_redeemed||0}))});
}catch(e){return NextResponse.json({error:e.message},{status:500})}}
export async function POST(req){try{
 if(req.headers.get('x-pmv2-owner-action')!=='promo')return NextResponse.json({error:'Invalid owner action.'},{status:403});
 const {code,percent_off,max_redemptions}=await req.json();
 const clean=String(code||'').trim().toUpperCase();
 const pct=Number(percent_off);
 if(!/^[A-Z0-9_-]{3,32}$/.test(clean))return NextResponse.json({error:'Use 3–32 letters, numbers, underscores or dashes.'},{status:400});
 if(!Number.isFinite(pct)||pct<=0||pct>100)return NextResponse.json({error:'Discount must be between 1 and 100%.'},{status:400});
 const coupon=await stripeRequest('/coupons',{method:'POST',body:{percent_off:String(pct),duration:'forever',name:'PMv2 '+clean}});
 const body={coupon:coupon.id,code:clean,active:'true'};
 const max=Number(max_redemptions);if(Number.isInteger(max)&&max>0)body.max_redemptions=String(max);
 const promo=await stripeRequest('/promotion_codes',{method:'POST',body});
 return NextResponse.json({ok:true,code:promo.code});
}catch(e){return NextResponse.json({error:e.message||'Unable to create promotion code.'},{status:400})}}
