import {NextResponse} from 'next/server';import {stripeReady,stripeRequest} from '../../../../lib/stripeServer';
export const runtime='nodejs';
export async function GET(){try{if(!stripeReady())return NextResponse.json({configured:false});const [balance,payouts]=await Promise.all([stripeRequest('/balance'),stripeRequest('/payouts?limit=10')]);return NextResponse.json({configured:true,balance,payouts:payouts.data||[]});}catch(e){return NextResponse.json({error:e.message},{status:500})}}
