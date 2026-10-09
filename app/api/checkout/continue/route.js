import { NextResponse } from 'next/server';
import { publicOrigin } from '../../../../lib/origin';
import { getResolvedCatalog } from '../../../../lib/catalogServer';
import { getBasket, addBasketPackage, validBasketIdent, basketAuthorized, tebexReady } from '../../../../lib/tebex';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Step 2 of checkout: Tebex sends the player back here after the FiveM sign-in.
// Add the cart that was saved in the basket, then hand over to Tebex's payment page.
export async function GET(req) {
  const origin = publicOrigin(req);
  const back = code => NextResponse.redirect(origin + '/checkout?checkout_error=' + code);
  const ident = new URL(req.url).searchParams.get('basket') || '';
  if (!tebexReady() || !validBasketIdent(ident)) return back('expired');

  try {
    let basket = await getBasket(ident);
    if (basket?.complete) return NextResponse.redirect(origin + '/checkout/success');
    if (!basketAuthorized(basket)) return back('signin');

    const saved = Array.isArray(basket?.custom?.cart) ? basket.custom.cart : [];
    if (!(basket.packages || []).length) {
      if (!saved.length) return back('expired');
      const catalog = await getResolvedCatalog();
      for (const row of saved.slice(0, 20)) {
        const product = catalog.find(p => p.slug === row.s);
        if (!product || !product.active || !product.tebex_package_id) return back('unavailable');
        const qty = Math.max(1, Math.min(product.max_quantity || 10, Math.floor(Number(row.q) || 1)));
        basket = await addBasketPackage(ident, product.tebex_package_id, qty);
      }
    }

    const checkout = basket?.links?.checkout || (await getBasket(ident))?.links?.checkout;
    if (!checkout) return back('failed');
    return NextResponse.redirect(checkout);
  } catch (e) {
    console.error('[checkout/continue]', e.message, e.body ? JSON.stringify(e.body).slice(0, 500) : '');
    return back('failed');
  }
}
