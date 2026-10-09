import { NextResponse } from 'next/server';
import { publicOrigin } from '../../../../lib/origin';
import { getBasket, validBasketIdent, basketAuthorized, tebexReady } from '../../../../lib/tebex';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Tebex sends the player back here after they sign in with their FiveM account.
export async function GET(req) {
  const origin = publicOrigin(req);
  const ident = new URL(req.url).searchParams.get('basket') || '';
  if (!tebexReady() || !validBasketIdent(ident)) return NextResponse.redirect(origin + '/checkout?checkout_error=expired');

  try {
    const basket = await getBasket(ident);
    if (basket?.complete) return NextResponse.redirect(origin + '/checkout/success');
    if (basketAuthorized(basket) && basket?.links?.checkout) return NextResponse.redirect(basket.links.checkout);
    return NextResponse.redirect(origin + '/checkout?checkout_error=signin');
  } catch {
    return NextResponse.redirect(origin + '/checkout?checkout_error=failed');
  }
}
