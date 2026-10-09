import { NextResponse } from 'next/server';
import { getResolvedCatalog } from '../../../lib/catalogServer';
import { publicOrigin } from '../../../lib/origin';
import { readCustomer } from '../../../lib/customerSession';
import {
  tebexReady, createBasket, addBasketPackage, getBasketAuthUrl, basketAuthorized, clientIp
} from '../../../lib/tebex';

const step = (name, promise) => promise.catch(e => { e.message = e.message.replace(/^Tebex:/, `Tebex (${name}):`); throw e; });

export const runtime = 'nodejs';

const BASKET_COOKIE = 'pmv2_basket';

// Builds a Tebex basket from the cart, then sends the player to sign in with their
// FiveM (Cfx.re) account on Tebex, then to Tebex's secure checkout.
export async function POST(req) {
  try {
    if (!tebexReady()) return NextResponse.json({ error: 'Checkout is not configured yet.' }, { status: 503 });

    const { items } = await req.json().catch(() => ({}));
    if (!Array.isArray(items) || !items.length) return NextResponse.json({ error: 'Cart is empty.' }, { status: 400 });
    if (items.length > 20) return NextResponse.json({ error: 'Too many different items in one order.' }, { status: 400 });

    const catalog = await getResolvedCatalog();
    const rows = items.map(row => {
      const product = catalog.find(p => p.slug === row.slug);
      if (!product || !product.active || !product.tebex_package_id) throw new Error('One or more store items are unavailable.');
      const qty = Math.max(1, Math.min(product.max_quantity || 10, Math.floor(Number(row.qty) || 1)));
      return { product, qty };
    });

    const origin = publicOrigin(req);
    const customer = readCustomer(req); // optional - only used for our own records
    const basket = await step('create basket', createBasket({
      ipAddress: clientIp(req),
      completeUrl: origin + '/checkout/success',
      cancelUrl: origin + '/checkout?canceled=1',
      custom: {
        source: 'projectmisfitsrp.com',
        ...(customer ? { discord_id: customer.id, discord_username: String(customer.username || '').slice(0, 64) } : {})
      }
    }));

    let current = basket;
    for (const r of rows) {
      current = await step('add ' + r.product.title, addBasketPackage(basket.ident, r.product.tebex_package_id, r.qty));
    }

    let url = basketAuthorized(current) ? current?.links?.checkout : null;
    if (!url) {
      url = await step('sign-in link', getBasketAuthUrl(basket.ident, origin + '/api/checkout/continue?basket=' + encodeURIComponent(basket.ident)));
    }
    if (!url) url = current?.links?.checkout || basket?.links?.checkout;
    if (!url) throw new Error('Tebex did not return a checkout link. Please try again.');

    const res = NextResponse.json({ url });
    res.cookies.set(BASKET_COOKIE, basket.ident, {
      httpOnly: true, sameSite: 'lax', secure: origin.startsWith('https'), path: '/', maxAge: 60 * 60 * 24
    });
    return res;
  } catch (e) {
    console.error('[checkout]', e.message, e.body ? JSON.stringify(e.body).slice(0, 500) : '');
    return NextResponse.json({ error: e.message || 'Unable to start checkout.' }, { status: 400 });
  }
}
