import { allStoreItems } from './products';
import { headers } from 'next/headers';
import { getTebexPackages, matchPackage, formatPrice, tebexReady, clientIp } from './tebex';

// The visitor's IP inside a page / route, so prices come back in their currency (CAD in Canada).
export async function visitorIp() {
  try { return clientIp(await headers()); } catch { return null; }
}

// Site products (artwork, copy, deliverables) + live price/availability from Tebex.
// A product can be bought only when a matching package exists in the Tebex store.
// Unmatched products show as COMING SOON, so nothing can be sold outside Tebex.
export async function getResolvedCatalog({ ip } = {}) {
  let packages = [];
  let tebexError = null;
  if (tebexReady()) {
    try {
      packages = await getTebexPackages({ ip: ip === undefined ? await visitorIp() : ip });
    } catch (e) {
      tebexError = e.message;
    }
  }

  return allStoreItems.map(local => {
    const pkg = packages.length ? matchPackage(local, packages) : null;
    if (!pkg) {
      return { ...local, price: 'COMING SOON', active: false, tebex_package_id: null, tebex_error: tebexError };
    }
    const amount = Number(pkg.base_price ?? pkg.total_price);
    return {
      ...local,
      price: formatPrice(amount, pkg.currency) || local.price,
      amount,
      currency: pkg.currency || 'USD',
      active: true,
      tebex_package_id: String(pkg.id),
      tebex_name: pkg.name,
      max_quantity: pkg.disable_quantity ? 1 : 10
    };
  });
}

// Owner dashboard: which site products are wired to which Tebex packages.
export async function getTebexMatchReport() {
  if (!tebexReady()) return { configured: false, items: [], unmatchedTebex: [] };
  const packages = await getTebexPackages({ fresh: true });
  const used = new Set();
  const items = allStoreItems.map(local => {
    const pkg = matchPackage(local, packages);
    if (pkg) used.add(String(pkg.id));
    return {
      slug: local.slug,
      title: local.title,
      category: local.category,
      tebex: pkg ? { id: String(pkg.id), name: pkg.name, price: formatPrice(pkg.base_price ?? pkg.total_price, pkg.currency) } : null
    };
  });
  const unmatchedTebex = packages
    .filter(p => !used.has(String(p.id)))
    .map(p => ({ id: String(p.id), name: p.name, price: formatPrice(p.base_price ?? p.total_price, p.currency) }));
  return { configured: true, items, unmatchedTebex };
}
