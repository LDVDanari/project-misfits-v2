// Tebex Headless API (https://docs.tebex.io/developers/headless-api)
// Tebex is the payment processor: it hosts checkout, takes the payment, handles
// refunds/chargebacks and runs the delivery command on the FiveM server.
// This site only builds the basket and sends the player to Tebex.
//
// Env: TEBEX_PUBLIC_TOKEN  - Tebex control panel -> Integrations -> Headless API -> Public token
//      TEBEX_PACKAGE_MAP   - optional JSON {"site-slug": tebexPackageId} when names don't match

const BASE = (process.env.TEBEX_API_BASE || 'https://headless.tebex.io/api').replace(/\/+$/, '');
const IDENT_RE = /^[A-Za-z0-9_-]{6,128}$/;

export function tebexToken() {
  return String(process.env.TEBEX_PUBLIC_TOKEN || '').trim();
}

export function tebexReady() {
  return /^[A-Za-z0-9_-]{6,}$/.test(tebexToken());
}

export function validBasketIdent(ident) {
  return IDENT_RE.test(String(ident || ''));
}

async function call(path, { method = 'GET', body, scoped = true } = {}) {
  const url = scoped ? `${BASE}/accounts/${encodeURIComponent(tebexToken())}${path}` : `${BASE}${path}`;
  const res = await fetch(url, {
    method,
    headers: { Accept: 'application/json', ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    cache: 'no-store',
    signal: AbortSignal.timeout(15000)
  });
  const json = await res.json().catch(() => null);
  if (!res.ok) {
    const parts = [json?.title, json?.detail, json?.message, json?.error_message].filter(Boolean);
    const detail = [...new Set(parts)].join(' - ') || `HTTP ${res.status}`;
    const err = new Error(`Tebex: ${detail}`);
    err.status = res.status;
    err.body = json;
    throw err;
  }
  return json;
}

// ---------- packages ----------

let packageCache = { at: 0, list: null };

export async function getTebexPackages({ fresh = false } = {}) {
  if (!tebexReady()) return [];
  if (!fresh && packageCache.list && Date.now() - packageCache.at < 60_000) return packageCache.list;
  const json = await call('/packages');
  const list = Array.isArray(json?.data) ? json.data : [];
  packageCache = { at: Date.now(), list };
  return list;
}

const norm = s => String(s || '').toLowerCase().replace(/[^a-z0-9]/g, '');

function packageMap() {
  try {
    const raw = String(process.env.TEBEX_PACKAGE_MAP || '').trim();
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

// Finds the Tebex package for a site product: explicit map first, then same name, then same slug.
export function matchPackage(product, packages, map = packageMap()) {
  const mapped = map[product.slug];
  if (mapped !== undefined && mapped !== null && mapped !== '') {
    return packages.find(p => String(p.id) === String(mapped)) || null;
  }
  const title = norm(product.title);
  const exact =
    packages.find(p => norm(p.name) === title) ||
    packages.find(p => p.slug && norm(p.slug) === norm(product.slug));
  if (exact) return exact;

  // Coin packs: any Tebex package with "coin" in the name and the same amount
  // ("10 Coins", "Misfit Coins x10", "10x Misfits Coins", "Coins - 10" ...).
  if (product.category === 'MISFIT COINS') {
    const amount = firstNumber(product.title);
    const coinPkgs = packages.filter(p => /coin/i.test(String(p.name || '')));
    return coinPkgs.find(p => firstNumber(p.name) === amount) || null;
  }
  return null;
}

function firstNumber(text) {
  const m = String(text || '').replace(/,/g, '').match(/\d+/);
  return m ? Number(m[0]) : null;
}

export function formatPrice(amount, currency = 'USD') {
  const n = Number(amount);
  if (!Number.isFinite(n)) return null;
  try {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: String(currency || 'USD').toUpperCase(),
      minimumFractionDigits: Number.isInteger(n) ? 0 : 2
    }).format(n);
  } catch {
    return '$' + n.toFixed(Number.isInteger(n) ? 0 : 2);
  }
}

// ---------- baskets ----------

// Tebex wants the buyer's IP when the basket is made from a server (for tax + fraud checks).
export async function createBasket({ completeUrl, cancelUrl, custom, ipAddress }) {
  const ip = validIp(ipAddress) ? ipAddress : null;
  const json = await call('/baskets' + (ip ? `?ip_address=${encodeURIComponent(ip)}` : ''), {
    method: 'POST',
    body: {
      complete_url: completeUrl,
      cancel_url: cancelUrl,
      complete_auto_redirect: true,
      custom: custom || {},
      ...(ip ? { ip_address: ip } : {})
    }
  });
  return json.data;
}

function validIp(ip) {
  const v = String(ip || '');
  return /^(\d{1,3}\.){3}\d{1,3}$/.test(v) || (/^[0-9a-f:]+$/i.test(v) && v.includes(':'));
}

// First public IP in the proxy chain (Coolify/Traefik/Cloudflare put the visitor first).
export function clientIp(req) {
  const h = name => req.headers.get(name) || '';
  const list = [h('cf-connecting-ip'), ...h('x-forwarded-for').split(','), h('x-real-ip')]
    .map(s => s.trim().replace(/^::ffff:/, ''))
    .filter(Boolean);
  const isPrivate = ip => /^(10\.|127\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|::1$|fc|fd)/i.test(ip);
  return list.find(ip => validIp(ip) && !isPrivate(ip)) || list.find(validIp) || null;
}

export async function addBasketPackage(ident, packageId, quantity) {
  const json = await call(`/baskets/${encodeURIComponent(ident)}/packages`, {
    method: 'POST',
    scoped: false,
    body: { package_id: Number(packageId), quantity: Math.max(1, Math.floor(Number(quantity) || 1)) }
  }).catch(async err => {
    // Some packages are in "dynamic" categories and need the flag.
    if (err.status === 422) {
      return call(`/baskets/${encodeURIComponent(ident)}/packages`, {
        method: 'POST',
        scoped: false,
        body: { package_id: Number(packageId), quantity: Math.max(1, Math.floor(Number(quantity) || 1)), dynamic: true }
      });
    }
    throw err;
  });
  return json.data;
}

export async function getBasket(ident) {
  const json = await call(`/baskets/${encodeURIComponent(ident)}`);
  return json.data;
}

// Tebex needs the buyer to sign in (Cfx.re / FiveM account) so it knows who to deliver to.
export async function getBasketAuthUrl(ident, returnUrl) {
  const json = await call(`/baskets/${encodeURIComponent(ident)}/auth?returnUrl=${encodeURIComponent(returnUrl)}`);
  const options = Array.isArray(json) ? json : Array.isArray(json?.data) ? json.data : [];
  const preferred =
    options.find(o => /fivem|cfx/i.test(String(o.name || ''))) ||
    options[0];
  return preferred?.url || null;
}

export function basketAuthorized(basket) {
  return Boolean(basket && (basket.username || basket.username_id));
}
