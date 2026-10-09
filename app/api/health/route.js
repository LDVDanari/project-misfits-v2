import { tebexReady, getTebexPackages, createBasket, addBasketPackage, clientIp, tebexToken, tebexPrivateKey } from '../../../lib/tebex';
import { dbReady } from '../../../lib/db';
import { customerLoginReady } from '../../../lib/customerSession';
import { getResolvedCatalog } from '../../../lib/catalogServer';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

// Shows which store settings the running app can see (names only, never values),
// so setup problems in Coolify are easy to spot.
let lastCheckoutTest = 0;

// /api/health?checkout=1 builds a throwaway Tebex basket (nothing is charged) and reports
// each step, so checkout problems can be diagnosed without clicking through the store.
async function checkoutTest(req) {
  if (Date.now() - lastCheckoutTest < 30_000) return { skipped: 'ran less than 30s ago' };
  lastCheckoutTest = Date.now();
  const out = { tokenLength: tebexToken().length, privateKey: Boolean(tebexPrivateKey()), steps: [] };
  const run = async (name, fn) => {
    try {
      const value = await fn();
      out.steps.push({ step: name, ok: true });
      return value;
    } catch (e) {
      out.steps.push({ step: name, ok: false, status: e.status || null, error: e.message, tebex: e.body || null });
      return null;
    }
  };
  const catalog = await getResolvedCatalog();
  const item = catalog.filter(x => x.active && x.tebex_package_id).sort((a, b) => (a.amount || 0) - (b.amount || 0))[0];
  if (!item) { out.steps.push({ step: 'find package', ok: false, error: 'No live items' }); return out; }
  const origin = (process.env.NEXT_PUBLIC_SITE_URL || 'https://projectmisfitsrp.com').replace(/\/+$/, '');
  const ip = clientIp(req);
  out.ipSent = Boolean(ip && tebexPrivateKey());
  const basket = await run('create basket', () => createBasket({
    ipAddress: ip, completeUrl: origin + '/checkout/success', cancelUrl: origin + '/checkout', custom: { source: 'health-check' }
  }));
  if (!basket) return out;
  out.basketHasIdent = Boolean(basket.ident);
  const added = await run(`add ${item.title} (#${item.tebex_package_id})`, () => addBasketPackage(basket.ident, item.tebex_package_id, 1));
  if (added) out.basketTotal = added.total_price;
  const base = (process.env.TEBEX_API_BASE || 'https://headless.tebex.io/api').replace(/\/+$/, '');
  const auth = await run('sign-in link', async () => {
    const res = await fetch(`${base}/accounts/${encodeURIComponent(tebexToken())}/baskets/${encodeURIComponent(basket.ident)}/auth?returnUrl=${encodeURIComponent(origin + '/checkout')}`, { headers: { Accept: 'application/json' }, cache: 'no-store' });
    const json = await res.json().catch(() => null);
    if (!res.ok) { const e = new Error(`HTTP ${res.status}`); e.status = res.status; e.body = json; throw e; }
    return json;
  });
  if (auth) {
    const list = Array.isArray(auth) ? auth : Array.isArray(auth?.data) ? auth.data : [];
    out.signInOptions = list.map(o => ({ name: o.name, host: (() => { try { return new URL(o.url).host; } catch { return null; } })() }));
  }
  return out;
}

export async function GET(req) {
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

  const test = tebexReady() && new URL(req.url).searchParams.get('checkout') === '1'
    ? await checkoutTest(req).catch(e => ({ error: e.message }))
    : undefined;

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
    },
    ...(test ? { checkoutTest: test } : {})
  }, { headers: { 'Cache-Control': 'no-store' } });
}
