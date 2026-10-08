'use client';
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { useCart } from './CartProvider';
import { DISCORD_URL } from '../lib/site';

const money = (n, c = 'usd') => new Intl.NumberFormat('en-US', { style: 'currency', currency: String(c || 'usd').toUpperCase() }).format((n || 0) / 100);

export default function CheckoutSuccess() {
  const c = useCart(), params = useSearchParams();
  const [order, setOrder] = useState(null), [error, setError] = useState(''), [copied, setCopied] = useState(false);
  const id = params.get('session_id') || '';

  useEffect(() => {
    if (!id) { setError('Missing order reference.'); return; }
    let tries = 0, timer = null, stopped = false;
    const load = () => fetch('/api/checkout/session?session_id=' + encodeURIComponent(id), { cache: 'no-store' })
      .then(async r => {
        const j = await r.json();
        if (!r.ok) throw new Error(j.error || 'Unable to verify order.');
        if (stopped) return;
        setOrder(j);
        if (j.paid) c?.clear?.();
        // The order code appears a few seconds after payment, once Stripe tells us about it.
        if (j.paid && !j.order_ref && tries++ < 15) timer = setTimeout(load, 2000);
      })
      .catch(e => !stopped && setError(e.message));
    load();
    return () => { stopped = true; clearTimeout(timer); };
  }, [id]);

  const ref = order?.order_ref || '';
  const copy = async () => { try { await navigator.clipboard.writeText(ref || order?.id || id); setCopied(true); setTimeout(() => setCopied(false), 1800); } catch { /* clipboard blocked */ } };

  if (error) return <div className="checkoutSuccess"><div className="successMark fail">!</div><h1>ORDER <span>LOOKUP FAILED.</span></h1><p>{error}</p><div className="actions"><Link className="primary" href="/store">BACK TO STORE</Link><a className="gold" href={DISCORD_URL} target="_blank" rel="noreferrer">PURCHASE SUPPORT</a></div></div>;
  if (!order) return <div className="checkoutSuccess"><div className="fundsLoading">Verifying payment…</div></div>;

  const hasCoins = order.items.some(it => it.category === 'MISFIT COINS');
  const hasPriority = order.items.some(it => it.category === 'PRIORITY');
  const needsSetup = order.items.some(it => !['MISFIT COINS', 'PRIORITY'].includes(it.category));

  return <div className="checkoutSuccess orderConfirmation">
    <div className={order.paid ? 'successMark' : 'successMark fail'}>{order.paid ? '✓' : '!'}</div>
    <div className="kicker">{order.paid ? 'PAYMENT VERIFIED' : 'PAYMENT STATUS'}</div>
    <h1>{order.paid ? 'ORDER' : 'PAYMENT'} <span>{order.paid ? 'CONFIRMED.' : String(order.payment_status || 'PENDING').toUpperCase() + '.'}</span></h1>
    <p>{order.paid ? 'Your payment is confirmed. Keep your order code below for support.' : 'Stripe has not marked this checkout as paid yet.'}</p>
    <section className="confirmationCard">
      <div className="confirmationTop">
        <div><small>ORDER CODE</small><code className={ref ? 'orderRef' : ''}>{ref || (order.paid ? 'Creating your order code…' : order.id)}</code></div>
        <button onClick={copy}>{copied ? 'COPIED' : 'COPY CODE'}</button>
      </div>
      <div className="confirmationMeta">
        <span><small>TOTAL</small><b>{money(order.amount_total, order.currency)}</b></span>
        {order.discord_username && <span><small>DELIVERED TO DISCORD</small><b>{order.discord_username}</b></span>}
        <span><small>RECEIPT EMAIL</small><b>{order.email || 'Not provided'}</b></span>
      </div>
      <div className="confirmationItems">{order.items.map((it, i) => <article key={i}><div><b>{it.qty}× {it.title}</b><small>{it.category}</small></div><p>{it.delivery}</p></article>)}</div>
    </section>
    <section className="fulfillmentBox">
      <div className="kicker">WHAT HAPPENS NEXT?</div>
      <h2>DELIVERY</h2>
      {hasCoins && <p>Your Misfit Coins are already on your account. Type <b>/coins</b> in the city to see your balance.</p>}
      {hasPriority && <p>Your priority is active on your Discord account.</p>}
      {needsSetup && <p>Packages need staff setup. Open purchase support in the Discord and give staff your order code so they can get you set up.</p>}
      {needsSetup && <a className="primary" href={DISCORD_URL} target="_blank" rel="noreferrer">OPEN PURCHASE SUPPORT</a>}
      {!needsSetup && <a className="gold" href={DISCORD_URL} target="_blank" rel="noreferrer">NEED HELP? PURCHASE SUPPORT</a>}
    </section>
    <div className="actions"><Link className="gold" href="/store">BACK TO STORE</Link><Link className="gold" href="/">HOME</Link></div>
  </div>;
}
