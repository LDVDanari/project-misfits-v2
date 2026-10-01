'use client';import {useEffect,useState} from 'react';import Link from 'next/link';import {useSearchParams} from 'next/navigation';import {useCart} from './CartProvider';import {DISCORD_URL} from '../lib/site';
const money=(n,c='usd')=>new Intl.NumberFormat('en-US',{style:'currency',currency:String(c||'usd').toUpperCase()}).format((n||0)/100);
export default function CheckoutSuccess(){
 const c=useCart(),params=useSearchParams();const [order,setOrder]=useState(null),[error,setError]=useState(''),[copied,setCopied]=useState(false);
 const id=params.get('session_id')||'';
 useEffect(()=>{if(!id){setError('Missing order reference.');return}fetch('/api/checkout/session?session_id='+encodeURIComponent(id),{cache:'no-store'}).then(async r=>{const j=await r.json();if(!r.ok)throw new Error(j.error||'Unable to verify order.');setOrder(j);if(j.paid)c?.clear?.()}).catch(e=>setError(e.message))},[id]);
 const copy=async()=>{try{await navigator.clipboard.writeText(order?.id||id);setCopied(true);setTimeout(()=>setCopied(false),1800)}catch{}};
 if(error)return <div className="checkoutSuccess"><div className="successMark fail">!</div><h1>ORDER <span>LOOKUP FAILED.</span></h1><p>{error}</p><div className="actions"><Link className="primary" href="/store">BACK TO STORE</Link><a className="gold" href={DISCORD_URL} target="_blank" rel="noreferrer">PURCHASE SUPPORT</a></div></div>;
 if(!order)return <div className="checkoutSuccess"><div className="fundsLoading">Verifying payment…</div></div>;
 return <div className="checkoutSuccess orderConfirmation">
   <div className={order.paid?'successMark':'successMark fail'}>{order.paid?'✓':'!'}</div>
   <div className="kicker">{order.paid?'PAYMENT VERIFIED':'PAYMENT STATUS'}</div>
   <h1>{order.paid?'ORDER':'PAYMENT'} <span>{order.paid?'CONFIRMED.':String(order.payment_status||'PENDING').toUpperCase()+'.'}</span></h1>
   <p>{order.paid?'Your payment is confirmed. Keep the order reference below for fulfillment and support.':'Stripe has not marked this checkout as paid yet.'}</p>
   <section className="confirmationCard">
    <div className="confirmationTop"><div><small>ORDER REFERENCE</small><code>{order.id}</code></div><button onClick={copy}>{copied?'COPIED':'COPY ID'}</button></div>
    <div className="confirmationMeta"><span><small>TOTAL</small><b>{money(order.amount_total,order.currency)}</b></span><span><small>EMAIL</small><b>{order.email||'Not provided'}</b></span></div>
    <div className="confirmationItems">{order.items.map((it,i)=><article key={i}><div><b>{it.qty}× {it.title}</b><small>{it.category}</small></div><p>{it.delivery}</p></article>)}</div>
   </section>
   <section className="fulfillmentBox"><div className="kicker">WHAT HAPPENS NEXT?</div><h2>FULFILLMENT & SUPPORT</h2><p>For packages that require setup, join the Project Misfits Discord and open purchase support. Include your order reference so staff can verify the payment quickly. Misfit Coin/account deliveries are handled after transaction verification.</p><a className="primary" href={DISCORD_URL} target="_blank" rel="noreferrer">OPEN PURCHASE SUPPORT</a></section>
   <div className="actions"><Link className="gold" href="/store">BACK TO STORE</Link><Link className="gold" href="/">HOME</Link></div>
 </div>
}