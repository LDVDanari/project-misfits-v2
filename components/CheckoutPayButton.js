'use client';
import { useEffect, useState } from 'react';
import { useCart } from './CartProvider';

const CHECKOUT_ERRORS = {
  signin: 'Tebex needs you to sign in with your FiveM account before paying. Press continue to try again.',
  expired: 'That checkout expired. Press continue to start a new one.',
  failed: 'Something went wrong talking to Tebex. Please try again.'
};

export default function CheckoutPayButton() {
  const c = useCart();
  const [loading, setLoading] = useState(false), [error, setError] = useState('');

  useEffect(() => {
    const code = new URLSearchParams(window.location.search).get('checkout_error');
    if (code) setError(CHECKOUT_ERRORS[code] || CHECKOUT_ERRORS.failed);
  }, []);

  const go = async () => {
    if (!c?.items?.length) return;
    setLoading(true); setError('');
    try {
      const r = await fetch('/api/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ items: c.items.map(x => ({ slug: x.slug, qty: x.qty })) })
      });
      const j = await r.json();
      if (!r.ok) throw new Error(j.error || 'Checkout failed');
      window.location.href = j.url;
    } catch (e) { setError(e.message); setLoading(false); }
  };

  return (
    <div className="payBlock">
      <button className="primary checkoutPay" onClick={go} disabled={loading}>
        {loading ? 'OPENING SECURE CHECKOUT…' : 'CONTINUE TO CHECKOUT'}
      </button>
      {error && <p className="checkoutError">{error}</p>}
      <small>Next you&apos;ll sign in with the <b>FiveM account you play on</b>, then pay on Tebex. Payments are processed by Tebex, PMv2&apos;s official FiveM store partner. Card details never touch PMv2.</small>
    </div>
  );
}
