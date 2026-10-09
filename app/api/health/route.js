import { tebexReady, getTebexPackages } from '../../../lib/tebex';
import { dbReady } from '../../../lib/db';
import { customerLoginReady } from '../../../lib/customerSession';
import { getResolvedCatalog } from '../../../lib/catalogServer';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

// Shows which store settings the running app can see (names only, never values),
// so setup problems in Coolify are easy to spot.
export async function GET() {
  const has = k => Boolean(String(process.env[k] || '').trim());
  const missing = [];
  if (!tebexReady()) missing.push('TEBEX_PUBLIC_TOKEN');

  let tebexReachable = false, tebexPackages = 0, liveItems = 0, tebexError = null;
  if (tebexReady()) {
    try {
      tebexPackages = (await getTebexPackages()).length;
      tebexReachable = true;
      liveItems = (await getResolvedCatalog()).filter(x => x.active).length;
    } catch (e) {
      tebexError = e.message;
    }
  }

  return Response.json({
    ok: true,
    service: 'project-misfits-v2-web',
    version: '3.0.0',
    store: {
      processor: 'tebex',
      tebex: tebexReady(),
      tebexReachable,
      tebexPackages,
      liveItems,
      ...(tebexError ? { tebexError } : {}),
      checkoutReady: tebexReachable && liveItems > 0,
      // optional extras: coin balance on the checkout page
      database: dbReady(),
      discordLogin: customerLoginReady(),
      missing
    }
  }, { headers: { 'Cache-Control': 'no-store' } });
}
