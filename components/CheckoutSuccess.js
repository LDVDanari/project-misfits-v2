'use client';
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useCart } from './CartProvider';
import { DISCORD_URL } from '../lib/site';

const money = (n, c = 'USD') => {
  try { return new Intl.NumberFormat('en-US', { style: 'currency', currency: String(c || 'USD').toUpperCase() }).format(Number(n) || 0); }
  catch { return '$' + (Number(n) || 0).toFixed(2); }
};

export default function CheckoutSuccess() {
  const c = useCart();
  const [order, setOrder] = useState(null), [error, setError] = useState(''), [copied, setCopied] = useState(false);

  useEffect(() => {
    let tries = 0, timer = null, stopped = false;
    const load = () => fetch('/api/checkout/basket', { cache: 'no-store' })
      .then(async r => {
        const j = await r.json();
        if (!r.ok) throw new Error(j.error || 'Unable to load your order.');
        if (stopped) return;
        setOrder(j);
        if (j.paid) c?.clear?.();
        // Tebex can send you back a moment before the payment is marked complete.
        if (!j.paid && tries++ < 20) timer = setTimeout(load, 3000);
      })
      .catch(e => !stopped && setError(e.message));
    load();
    return () => { stopped = true; clearTimeout(timer); };
  }, []);

  const ref = order?.ident || '';
  const copy = async () => { try { await navigator.clipboard.writeText(ref); setCopied(true); setTimeout(() => setCopied(false), 1800); } catch { /* clipboard blocked */ } };

  if (error) return <div className="checkoutSuccess"><div className="successMark fail">!</div><h1>ORDER <span>LOOKUP FAILED.</span></h1><p>{error} If you paid, your Tebex receipt email has your transaction ID.</p><div className="actions"><Link className="primary" href="/store">BACK TO STORE</Link><a className="gold" href={DISCORD_URL} target="_blank" rel="noreferrer">PURCHASE SUPPORT</a></div></div>;
  if (!order) return <div className="checkoutSuccess"><div className="fundsLoading">Checking your payment with Tebex…</div></div>;

  const hasCoins = order.items.some(it => it.category === 'MISFIT COINS');
  const needsSetup = order.items.some(it => it.category && !['MISFIT COINS', 'PRIORITY'].includes(it.category));

  return <div className="checkoutSuccess orderConfirmation">
    <div className={order.paid ? 'successMark' : 'successMark fail'}>{order.paid ? '✓' : '…'}</div>
    <div className="kicker">{order.paid ? 'PAYMENT RECEIVED' : 'PAYMENT PROCESSING'}</div>
    <h1>{order.paid ? 'ORDER' : 'ALMOST'} <span>{order.paid ? 'CONFIRMED.' : 'THERE.'}</span></h1>
    <p>{order.paid
      ? 'Thanks for supporting Project Misfits! Tebex has your payment and emailed your receipt.'
      : 'Tebex is still confirming your payment. This page updates by itself. If it stays here, check your email for the Tebex receipt.'}</p>
    <section className="confirmationCard">
      <div className="confirmationTop">
        <div><small>BASKET REFERENCE</small><code className="orderRef">{ref}</code></div>
        <button onClick={copy}>{copied ? 'COPIED' : 'COPY'}</button>
      </div>
      <div className="confirmationMeta">
        {order.total !== null && <span><small>TOTAL</small><b>{money(order.total, order.currency)}</b></span>}
        {order.username && <span><small>DELIVERED TO FIVEM ACCOUNT</small><b>{order.username}</b></span>}
        <span><small>RECEIPT EMAIL</small><b>{order.email || 'Sent by Tebex'}</b></span>
      </div>
      <div className="confirmationItems">{order.items.map((it, i) => <article key={i}><div><b>{it.qty}× {it.title}</b><small>{it.category}</small></div><p>{it.delivery}</p></article>)}</div>
    </section>
    <section className="fulfillmentBox">
      <div className="kicker">WHAT HAPPENS NEXT?</div>
      <h2>DELIVERY</h2>
      {hasCoins && <p>Your Misfit Coins land in the city within a few minutes of payment. If you&apos;re offline they&apos;ll be waiting the next time you load in. Type <b>/coins</b> to check. Have <b>Discord open</b> when you launch FiveM so the city knows which account to credit.</p>}
      {needsSetup && <p>Packages need staff setup. Open purchase support in the Discord with your Tebex transaction ID from the receipt email.</p>}
      {needsSetup
        ? <a className="primary" href={DISCORD_URL} target="_blank" rel="noreferrer">OPEN PURCHASE SUPPORT</a>
        : <a className="gold" href={DISCORD_URL} target="_blank" rel="noreferrer">NEED HELP? PURCHASE SUPPORT</a>}
    </section>
    <div className="actions"><Link className="gold" href="/store">BACK TO STORE</Link><Link className="gold" href="/">HOME</Link></div>
  </div>;
}
