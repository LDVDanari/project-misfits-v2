'use client';
import Link from 'next/link';
import { useCart } from './CartProvider';
import CheckoutPayButton from './CheckoutPayButton';
import DiscordAccount, { useDiscordAccount } from './DiscordAccount';

import { priceNumber } from '../lib/money';

const lineTotal = x => priceNumber(x.price) * x.qty;

export default function CheckoutSummary() {
  const c = useCart();
  const account = useDiscordAccount();
  if (!c) return null;
  if (c.items.length === 0) return <div className="checkoutEmpty"><h2>YOUR CART IS EMPTY.</h2><p>Add store items before reviewing an order.</p><Link className="primary" href="/store">OPEN STORE</Link></div>;
  return <div className="checkoutLayout">
    <section className="checkoutItems">
      <div className="kicker">ORDER REVIEW</div>
      {c.items.map(x => <article key={x.slug}><div><b>{x.title}</b><small>{x.price} × {x.qty}</small></div><strong>{c.money(lineTotal(x))}</strong></article>)}
      <div className="checkoutTotal"><span>SUBTOTAL</span><b>{c.money(c.subtotal)}</b></div>
      <small className="checkoutTaxNote">Any sales tax is added by Tebex at checkout. Tebex charges in your country&apos;s currency (USD, or CAD in Canada).</small>
    </section>
    <aside className="checkoutNotice">
      <div className="kicker">SECURE CHECKOUT</div>
      <h2>READY TO PAY?</h2>
      <p>Your order is priced by Tebex, PMv2&apos;s official FiveM store partner. Coins are delivered to the FiveM account you sign in with, straight into the city.</p>
      <DiscordAccount account={account} />
      <CheckoutPayButton />
      <Link className="gold" href="/store">CONTINUE SHOPPING</Link>
    </aside>
  </div>;
}
