'use client';import {useEffect,useMemo,useState} from 'react';
const money=(n,c='usd')=>new Intl.NumberFormat('en-US',{style:'currency',currency:String(c||'usd').toUpperCase()}).format((n||0)/100);
const when=s=>s?new Date(s*1000).toLocaleString():'';
export default function OwnerFunds(){
 const [data,setData]=useState(null),[amount,setAmount]=useState(''),[msg,setMsg]=useState(''),[updating,setUpdating]=useState(''),[query,setQuery]=useState(''),[status,setStatus]=useState('all'),[busyRefund,setBusyRefund]=useState('');
 const load=()=>fetch('/api/owner/funds',{cache:'no-store'}).then(r=>r.json()).then(setData);
 useEffect(()=>{load()},[]);
 const withdraw=async()=>{setMsg('');const r=await fetch('/api/owner/payout',{method:'POST',headers:{'Content-Type':'application/json','X-PMv2-Owner-Action':'payout'},body:JSON.stringify({amount})});const j=await r.json();if(!r.ok){setMsg(j.error||'Payout failed');return}setMsg('Payout created: '+j.payout.id);setAmount('');load()};
 const setOrder=async(id,next)=>{setUpdating(id);setMsg('');const r=await fetch('/api/owner/order',{method:'POST',headers:{'Content-Type':'application/json','X-PMv2-Owner-Action':'order-status'},body:JSON.stringify({session_id:id,status:next})});const j=await r.json();if(!r.ok)setMsg(j.error||'Order update failed');else await load();setUpdating('')};
 const refund=async o=>{if(!o.payment_intent||o.refunded)return;if(!window.confirm('Refund '+money(o.amount_total,o.currency)+' for '+(o.customer_email||'this order')+'? This sends a real refund through Stripe.'))return;setBusyRefund(o.id);setMsg('');const r=await fetch('/api/owner/refund',{method:'POST',headers:{'Content-Type':'application/json','X-PMv2-Owner-Action':'refund'},body:JSON.stringify({payment_intent:o.payment_intent,order_id:o.id})});const j=await r.json();if(!r.ok)setMsg(j.error||'Refund failed');else setMsg('Refund created: '+j.refund.id);await load();setBusyRefund('')};
 const filtered=useMemo(()=>{const q=query.trim().toLowerCase();return(data?.orders||[]).filter(o=>{const matches=!q||[o.id,o.customer_name,o.customer_email,...(o.items||[]).map(i=>i.name)].join(' ').toLowerCase().includes(q);const s=o.refunded?'refunded':o.fulfillment_status;return matches&&(status==='all'||s===status)})},[data,query,status]);
 if(!data)return <div className="fundsLoading">Loading funds…</div>;
 if(data.configured===false)return <div className="notice">Stripe has not been connected yet. Add the private Stripe environment variables in Coolify to activate checkout and balances.</div>;
 if(data.error)return <div className="notice">{data.error}</div>;
 const available=(data.balance.available||[]).find(x=>x.currency==='usd')?.amount||0;
 const pending=(data.balance.pending||[]).find(x=>x.currency==='usd')?.amount||0;
 const m=data.metrics||{};
 return <>
  <div className="fundCards financeCards">
   <article><small>AVAILABLE</small><b>{money(available)}</b><span>Eligible for payout</span></article>
   <article><small>PENDING</small><b>{money(pending)}</b><span>Processing payments</span></article>
   <article><small>GROSS SALES</small><b>{money(m.gross)}</b><span>Recent processed charges</span></article>
   <article><small>PROCESSOR FEES</small><b>{money(m.fees)}</b><span>Recent Stripe fees</span></article>
   <article><small>NET SALES</small><b>{money(m.net)}</b><span>After processor fees</span></article>
   <article><small>REFUNDED</small><b>{money(m.refunds)}</b><span>Refunded from recent orders</span></article>
  </div>

  <section className="withdrawPanel">
   <div><div className="kicker">OWNER ONLY</div><h2>WITHDRAW FUNDS</h2><p>Payouts go to the verified payout destination on the connected merchant account.</p></div>
   <div className="withdrawControls"><label>$<input value={amount} onChange={e=>setAmount(e.target.value)} inputMode="decimal" placeholder="0.00"/></label><button className="primary" onClick={withdraw}>WITHDRAW</button></div>
   {msg&&<p className="withdrawMsg">{msg}</p>}
  </section>

  <section className="orderHistory">
   <div className="sectionTitle compact"><div><div className="kicker">FULFILLMENT</div><h2>RECENT <span>ORDERS.</span></h2></div><p>Search, fulfill and refund paid orders without leaving the owner dashboard.</p></div>
   <div className="orderToolbar">
    <input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search email, name, order ID or item…"/>
    <select value={status} onChange={e=>setStatus(e.target.value)}>
      <option value="all">ALL ORDERS</option><option value="new">NEW</option><option value="processing">PROCESSING</option><option value="fulfilled">FULFILLED</option><option value="refunded">REFUNDED</option>
    </select>
    <button onClick={load}>REFRESH</button>
   </div>
   {filtered.length?filtered.map(o=><article className={o.refunded?'ownerOrder refundedOrder':'ownerOrder'} key={o.id}>
    <div className="orderMain">
     <div><b>{o.customer_name||'Customer'}</b><small>{o.customer_email||'No email'} · {when(o.created)}</small></div>
     <div className="orderMoney"><strong>{money(o.amount_total,o.currency)}</strong>{o.fee>0&&<small>Fee {money(o.fee,o.currency)} · Net {money(o.net,o.currency)}</small>}{o.amount_refunded>0&&<small>Refunded {money(o.amount_refunded,o.currency)}</small>}</div>
    </div>
    <div className="orderItems">{(o.items||[]).map((it,i)=><span key={i}>{it.quantity}× {it.name}</span>)}</div>
    <div className="orderFoot">
     <code>{o.id}</code>
     <div className="orderActions">
      <select value={o.refunded?'refunded':o.fulfillment_status} disabled={updating===o.id||o.refunded} onChange={e=>setOrder(o.id,e.target.value)}>
       <option value="new">NEW</option><option value="processing">PROCESSING</option><option value="fulfilled">FULFILLED</option>{o.refunded&&<option value="refunded">REFUNDED</option>}
      </select>
      <button className="refundButton" disabled={!o.payment_intent||o.refunded||busyRefund===o.id} onClick={()=>refund(o)}>{o.refunded?'REFUNDED':busyRefund===o.id?'REFUNDING…':'REFUND'}</button>
     </div>
    </div>
   </article>):<p className="emptyOrders">No orders match your filters.</p>}
  </section>

  <section className="payoutHistory"><h2>PAYOUT HISTORY</h2>{data.payouts.length?data.payouts.map(p=><article key={p.id}><div><b>{money(p.amount,p.currency)}</b><small>{p.id}</small></div><span>{String(p.status||'').toUpperCase()}</span></article>):<p>No payouts yet.</p>}</section>
 </>;
}