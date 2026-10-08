'use client';
import { useState } from 'react';
import { useCart } from './CartProvider';
import { LOGIN_URL } from './DiscordAccount';

export default function CheckoutPayButton({ account }) {
  const c = useCart();
  const [loading, setLoading] = useState(false), [error, setError] = useState('');
  const loggedIn = Boolean(account?.user);

  const go = async () => {
    if (!c?.items?.length) return;
    if (!loggedIn) { window.location.href = LOGIN_URL; return; }
    setLoading(true); setError('');
    try {
      const r = await fetch('/api/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ items: c.items.map(x => ({ slug: x.slug, qty: x.qty })) })
      });
      const j = await r.json();
      if (r.status === 401 && j.login) { window.location.href = LOGIN_URL; return; }
      if (!r.ok) throw new Error(j.error || 'Checkout failed');
      window.location.href = j.url;
    } catch (e) { setError(e.message); setLoading(false); }
  };

  // Logged out: the "Log in with Discord" button above is the only thing to press.
  if (!loggedIn) return <div className="payBlock"><small>Card details are handled by the payment processor, not stored on PMv2.</small></div>;

  return (
    <div className="payBlock">
      <button className="primary checkoutPay" onClick={go} disabled={loading || account?.loading}>
        {loading ? 'OPENING SECURE CHECKOUT…' : 'PAY SECURELY'}
      </button>
      {error && <p className="checkoutError">{error}</p>}
      <small>Card details are handled by the payment processor, not stored on PMv2.</small>
    </div>
  );
}
