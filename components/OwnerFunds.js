'use client';import {useEffect,useState} from 'react';
const money=(n,c='usd')=>new Intl.NumberFormat('en-US',{style:'currency',currency:String(c||'usd').toUpperCase()}).format((n||0)/100);
const when=s=>s?new Date(s*1000).toLocaleString():'';
export default function OwnerFunds(){
 const [data,setData]=useState(null),[amount,setAmount]=useState(''),[msg,setMsg]=useState(''),[updating,setUpdating]=useState('');
 const load=()=>fetch('/api/owner/funds',{cache:'no-store'}).then(r=>r.json()).then(setData);
 useEffect(()=>{load()},[]);
 const withdraw=async()=>{setMsg('');const r=await fetch('/api/owner/payout',{method:'POST',headers:{'Content-Type':'application/json','X-PMv2-Owner-Action':'payout'},body:JSON.stringify({amount})});const j=await r.json();if(!r.ok){setMsg(j.error||'Payout failed');return}setMsg('Payout created: '+j.payout.id);setAmount('');load()};
 const setOrder=async(id,status)=>{setUpdating(id);setMsg('');const r=await fetch('/api/owner/order',{method:'POST',headers:{'Content-Type':'application/json','X-PMv2-Owner-Action':'order-status'},body:JSON.stringify({session_id:id,status})});const j=await r.json();if(!r.ok)setMsg(j.error||'Order update failed');else await load();setUpdating('')};
 if(!data)return <div className="fundsLoading">Loading funds…</div>;
 if(data.configured===false)return <div className="notice">Stripe has not been connected yet. Add the private Stripe environment variables in Coolify to activate checkout and balances.</div>;
 if(data.error)return <div className="notice">{data.error}</div>;
 const available=(data.balance.available||[]).find(x=>x.currency==='usd')?.amount||0;
 const pending=(data.balance.pending||[]).find(x=>x.currency==='usd')?.amount||0;
 return <>
  <div className="fundCards">
   <article><small>AVAILABLE</small><b>{money(available)}</b><span>Eligible for payout</span></article>
   <article><small>PENDING</small><b>{money(pending)}</b><span>Processing payments</span></article>
   <article><small>PAID ORDERS</small><b>{data.orders?.length||0}</b><span>Latest completed checkouts</span></article>
  </div>

  <section className="withdrawPanel">
   <div><div className="kicker">OWNER ONLY</div><h2>WITHDRAW FUNDS</h2><p>Payouts go to the verified payout destination on the connected merchant account.</p></div>
   <div className="withdrawControls"><label>$<input value={amount} onChange={e=>setAmount(e.target.value)} inputMode="decimal" placeholder="0.00"/></label><button className="primary" onClick={withdraw}>WITHDRAW</button></div>
   {msg&&<p className="withdrawMsg">{msg}</p>}
  </section>

  <section className="orderHistory">
   <div className="sectionTitle compact"><div><div className="kicker">FULFILLMENT</div><h2>RECENT <span>ORDERS.</span></h2></div><p>Paid Stripe checkouts appear here automatically.</p></div>
   {(data.orders||[]).length?(data.orders||[]).map(o=><article className="ownerOrder" key={o.id}>
    <div className="orderMain">
     <div><b>{o.customer_name||'Customer'}</b><small>{o.customer_email||'No email'} · {when(o.created)}</small></div>
     <strong>{money(o.amount_total,o.currency)}</strong>
    </div>
    <div className="orderItems">{(o.items||[]).map((it,i)=><span key={i}>{it.quantity}× {it.name}</span>)}</div>
    <div className="orderFoot">
     <code>{o.id}</code>
     <select value={o.fulfillment_status} disabled={updating===o.id} onChange={e=>setOrder(o.id,e.target.value)}>
      <option value="new">NEW</option><option value="processing">PROCESSING</option><option value="fulfilled">FULFILLED</option>
     </select>
    </div>
   </article>):<p className="emptyOrders">No completed orders yet.</p>}
  </section>

  <section className="payoutHistory"><h2>PAYOUT HISTORY</h2>{data.payouts.length?data.payouts.map(p=><article key={p.id}><div><b>{money(p.amount,p.currency)}</b><small>{p.id}</small></div><span>{String(p.status||'').toUpperCase()}</span></article>):<p>No payouts yet.</p>}</section>
 </>;
}