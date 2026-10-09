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
  let tebexPackageNames = [], unmatched = [];
  if (tebexReady()) {
    try {
      const pkgs = await getTebexPackages();
      tebexPackages = pkgs.length;
      tebexPackageNames = pkgs.slice(0, 30).map(p => String(p.name || ''));
      tebexReachable = true;
      const catalog = await getResolvedCatalog();
      liveItems = catalog.filter(x => x.active).length;
      const used = new Set(catalog.map(x => x.tebex_package_id).filter(Boolean));
      unmatched = pkgs.filter(p => !used.has(String(p.id))).slice(0, 30).map(p => String(p.name || ''));
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
      tebexPackageNames,
      ...(unmatched.length ? { tebexNotOnSite: unmatched } : {}),
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
