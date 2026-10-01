import {NextResponse} from 'next/server';import {getResolvedCatalog,upsertCatalogItem} from '../../../../lib/catalogServer';
export const runtime='nodejs';
export async function GET(){try{return NextResponse.json({items:await getResolvedCatalog()})}catch(e){return NextResponse.json({error:e.message},{status:500})}}
export async function POST(req){try{
 if(req.headers.get('x-pmv2-owner-action')!=='catalog')return NextResponse.json({error:'Invalid owner action.'},{status:403});
 const {slug,price,active}=await req.json();
 const item=await upsertCatalogItem(String(slug||''),{price,active});
 return NextResponse.json({ok:true,item});
}catch(e){return NextResponse.json({error:e.message||'Unable to update product.'},{status:400})}}
