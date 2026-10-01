import {NextResponse} from 'next/server';import {getResolvedCatalog} from '../../../../lib/catalogServer';
export const runtime='nodejs';
export async function GET(){try{return NextResponse.json({items:await getResolvedCatalog()})}catch(e){return NextResponse.json({error:e.message},{status:500})}}
