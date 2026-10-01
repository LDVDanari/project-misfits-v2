import {allStoreItems} from './products';import {stripeReady,stripeRequest,priceToCents} from './stripeServer';
const money=cents=>'$'+(cents/100).toFixed(cents%100?2:0);
export async function getStripeCatalogMap(){
 const map=new Map();
 if(!stripeReady())return map;
 try{
  const r=await stripeRequest('/products?limit=100');
  for(const p of r.data||[]){
   const slug=p.metadata?.pmv2_slug;
   if(slug)map.set(slug,p);
  }
 }catch{}
 return map;
}
export async function getResolvedCatalog(){
 const map=await getStripeCatalogMap();
 return allStoreItems.map(local=>{
  const remote=map.get(local.slug);
  const cents=Number(remote?.metadata?.pmv2_price_cents||'');
  const remotePrice=Number.isFinite(cents)&&cents>0?money(cents):null;
  const active=remote?Boolean(remote.active):local.price!=='COMING SOON';
  return{...local,price:remotePrice||local.price,active,stripe_product_id:remote?.id||null};
 });
}
export async function upsertCatalogItem(slug,{price,active}){
 const local=allStoreItems.find(p=>p.slug===slug);if(!local)throw new Error('Unknown store item');
 const map=await getStripeCatalogMap();let remote=map.get(slug);
 const cents=priceToCents(price);
 if(cents<50)throw new Error('Price must be at least $0.50');
 const body={name:local.title,active:String(Boolean(active)),'metadata[pmv2_slug]':slug,'metadata[pmv2_price_cents]':String(cents)};
 if(!remote)remote=await stripeRequest('/products',{method:'POST',body});
 else remote=await stripeRequest('/products/'+encodeURIComponent(remote.id),{method:'POST',body});
 return{slug,price:money(cents),active:Boolean(remote.active),stripe_product_id:remote.id};
}
