'use client';import {useEffect,useState} from 'react';
const dollars=p=>{const n=Number(String(p||'').replace(/[^0-9.]/g,''));return Number.isFinite(n)?String(n):''};
export default function OwnerStoreAdmin(){
 const [items,setItems]=useState([]),[drafts,setDrafts]=useState({}),[codes,setCodes]=useState([]),[msg,setMsg]=useState(''),[busy,setBusy]=useState(''),[promo,setPromo]=useState({code:'',percent_off:'10',max_redemptions:''});
 const load=async()=>{const [a,b]=await Promise.all([fetch('/api/owner/catalog',{cache:'no-store'}).then(r=>r.json()),fetch('/api/owner/promos',{cache:'no-store'}).then(r=>r.json())]);if(a.items){setItems(a.items);setDrafts(Object.fromEntries(a.items.map(x=>[x.slug,{price:dollars(x.price),active:x.active!==false}])))}if(b.codes)setCodes(b.codes)};
 useEffect(()=>{load()},[]);
 const save=async slug=>{setBusy(slug);setMsg('');const d=drafts[slug];const r=await fetch('/api/owner/catalog',{method:'POST',headers:{'Content-Type':'application/json','X-PMv2-Owner-Action':'catalog'},body:JSON.stringify({slug,price:d.price,active:d.active})});const j=await r.json();if(!r.ok)setMsg(j.error||'Product update failed');else{setMsg('Saved '+j.item.slug);await load()}setBusy('')};
 const createPromo=async e=>{e.preventDefault();setBusy('promo');setMsg('');const r=await fetch('/api/owner/promos',{method:'POST',headers:{'Content-Type':'application/json','X-PMv2-Owner-Action':'promo'},body:JSON.stringify(promo)});const j=await r.json();if(!r.ok)setMsg(j.error||'Promo creation failed');else{setMsg('Created code '+j.code);setPromo({code:'',percent_off:'10',max_redemptions:''});await load()}setBusy('')};
 return <section className="ownerStoreAdmin">
   <div className="sectionTitle compact"><div><div className="kicker">STORE CONTROL</div><h2>PRODUCTS & <span>DISCOUNTS.</span></h2></div><p>Change prices, enable or disable products, and create Stripe promotion codes.</p></div>
   {msg&&<div className="adminStoreMsg">{msg}</div>}
   <div className="catalogAdminGrid">
    {items.map(x=>{const d=drafts[x.slug]||{price:'',active:false};return <article key={x.slug} className="catalogAdminCard">
      <div className="catalogAdminHead"><div><small>{x.category}</small><h3>{x.title}</h3></div><span className={d.active?'liveBadge':'offBadge'}>{d.active?'LIVE':'OFF'}</span></div>
      <div className="catalogAdminControls">
       <label>PRICE ($)<input inputMode="decimal" value={d.price} onChange={e=>setDrafts(v=>({...v,[x.slug]:{...d,price:e.target.value}}))} placeholder="0.00"/></label>
       <label className="toggleLine"><input type="checkbox" checked={d.active} onChange={e=>setDrafts(v=>({...v,[x.slug]:{...d,active:e.target.checked}}))}/><span>AVAILABLE FOR PURCHASE</span></label>
       <button className="primary" disabled={busy===x.slug||!d.price} onClick={()=>save(x.slug)}>{busy===x.slug?'SAVING…':'SAVE PRODUCT'}</button>
      </div>
    </article>})}
   </div>
   <div className="promoAdmin">
    <div><div className="kicker">DISCOUNT CODES</div><h3>CREATE PROMOTION CODE</h3><p>Customers can enter these directly in Stripe Checkout.</p></div>
    <form onSubmit={createPromo}>
      <label>CODE<input value={promo.code} onChange={e=>setPromo(v=>({...v,code:e.target.value.toUpperCase()}))} placeholder="MISFIT10" required/></label>
      <label>DISCOUNT %<input inputMode="decimal" value={promo.percent_off} onChange={e=>setPromo(v=>({...v,percent_off:e.target.value}))} required/></label>
      <label>MAX USES<input inputMode="numeric" value={promo.max_redemptions} onChange={e=>setPromo(v=>({...v,max_redemptions:e.target.value}))} placeholder="Unlimited"/></label>
      <button className="gold" disabled={busy==='promo'}>{busy==='promo'?'CREATING…':'CREATE CODE'}</button>
    </form>
    <div className="promoList">{codes.length?codes.map(c=><article key={c.id}><b>{c.code}</b><span>{c.coupon?.percent_off?c.coupon.percent_off+'% OFF':'DISCOUNT'}</span><small>{c.active?'ACTIVE':'INACTIVE'} · {c.times_redeemed||0} USED{c.max_redemptions?' / '+c.max_redemptions:''}</small></article>):<p>No promotion codes yet.</p>}</div>
   </div>
 </section>
}