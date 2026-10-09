import { NextResponse } from 'next/server';
import { getBasket, validBasketIdent, tebexReady } from '../../../../lib/tebex';
import { getResolvedCatalog } from '../../../../lib/catalogServer';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Order status for the success page (the basket id comes from our own cookie).
export async function GET(req) {
  const ident = req.cookies.get('pmv2_basket')?.value || '';
  if (!tebexReady()) return NextResponse.json({ error: 'Checkout is not configured.' }, { status: 503 });
  if (!validBasketIdent(ident)) return NextResponse.json({ error: 'No recent order found on this browser.' }, { status: 404 });

  try {
    const b = await getBasket(ident);
    const catalog = await getResolvedCatalog().catch(() => []);
    const items = (b.packages || []).map(p => {
      const local = catalog.find(x => x.tebex_package_id === String(p.id));
      return {
        title: local?.title || p.name,
        qty: p.in_basket?.quantity || 1,
        category: local?.category || '',
        delivery: local?.delivery || ''
      };
    });
    return NextResponse.json({
      ident: b.ident,
      paid: Boolean(b.complete || b.links?.payment),
      complete: Boolean(b.complete),
      username: b.username || null,
      email: b.email || null,
      total: b.total_price ?? null,
      currency: b.currency || 'USD',
      items
    }, { headers: { 'Cache-Control': 'no-store' } });
  } catch (e) {
    return NextResponse.json({ error: e.message || 'Unable to load order.' }, { status: 400 });
  }
}
