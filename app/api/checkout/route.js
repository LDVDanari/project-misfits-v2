import { NextResponse } from 'next/server';
import { priceToCents, stripeRequest, stripeReady } from '../../../lib/stripeServer';
import { getResolvedCatalog } from '../../../lib/catalogServer';
import { publicOrigin } from '../../../lib/origin';
import { readCustomer } from '../../../lib/customerSession';
import { dbReady } from '../../../lib/db';

export const runtime = 'nodejs';

export async function POST(req) {
  try {
    if (!stripeReady()) return NextResponse.json({ error: 'Checkout is not configured yet.' }, { status: 503 });
    if (!dbReady()) return NextResponse.json({ error: 'Store delivery is not configured yet. Please try again soon.' }, { status: 503 });

    // Purchases are delivered to the Discord account the player uses in the city.
    const customer = readCustomer(req);
    if (!customer) {
      return NextResponse.json({ error: 'Log in with Discord first so we know where to deliver your order.', login: true }, { status: 401 });
    }

    const { items } = await req.json();
    const catalog = await getResolvedCatalog();
    if (!Array.isArray(items) || !items.length) return NextResponse.json({ error: 'Cart is empty.' }, { status: 400 });
    if (items.length > 20) return NextResponse.json({ error: 'Too many different items in one order.' }, { status: 400 });

    const rows = items.map(row => {
      const product = catalog.find(p => p.slug === row.slug);
      if (!product || !product.active || product.price === 'COMING SOON') throw new Error('One or more store items are unavailable.');
      const qty = Math.max(1, Math.min(10, Number(row.qty) || 1));
      return { product, qty, unit_amount: priceToCents(product.price) };
    });

    const origin = publicOrigin(req);
    let taxCode = process.env.STRIPE_TAX_CODE || '';
    if (!taxCode) {
      try { const taxSettings = await stripeRequest('/tax/settings'); taxCode = taxSettings?.defaults?.tax_code || ''; } catch { /* fall through */ }
    }
    if (!taxCode) return NextResponse.json({ error: 'Stripe tax code is not configured. Set a default tax code in Stripe Tax settings or STRIPE_TAX_CODE in Coolify.' }, { status: 503 });

    const body = {
      mode: 'payment',
      success_url: origin + '/checkout/success?session_id={CHECKOUT_SESSION_ID}',
      cancel_url: origin + '/checkout?canceled=1',
      allow_promotion_codes: 'true',
      client_reference_id: customer.id,
      'metadata[discord_id]': customer.id,
      'metadata[discord_username]': customer.username.slice(0, 100),
      'payment_intent_data[metadata][discord_id]': customer.id
    };
    rows.forEach((r, i) => {
      body[`line_items[${i}][price_data][currency]`] = 'usd';
      body[`line_items[${i}][price_data][unit_amount]`] = String(r.unit_amount);
      body[`line_items[${i}][price_data][product_data][name]`] = r.product.title;
      body[`line_items[${i}][price_data][product_data][description]`] = r.product.short || 'Project Misfits v2 store purchase';
      body[`line_items[${i}][price_data][product_data][tax_code]`] = taxCode;
      body[`line_items[${i}][price_data][product_data][metadata][pmv2_slug]`] = r.product.slug;
      body[`line_items[${i}][quantity]`] = String(r.qty);
      body[`metadata[item_${i}]`] = r.product.slug + ':' + r.qty;
    });

    const session = await stripeRequest('/checkout/sessions', { method: 'POST', body });
    return NextResponse.json({ url: session.url });
  } catch (e) {
    return NextResponse.json({ error: e.message || 'Unable to start checkout.' }, { status: 400 });
  }
}
