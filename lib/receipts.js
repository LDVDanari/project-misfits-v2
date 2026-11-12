// Tebex purchase webhooks -> private Discord receipt.
// Tebex calls /api/tebex/webhook when a payment completes. This site checks the
// signature, builds a small receipt (no email, no IP, no card details) and posts it
// to a staff-only Discord channel through a channel webhook. The PMv2 bot picks it
// up there, DMs the buyer a receipt card and swaps the raw post for a staff log card.
// Using a Discord webhook means the bot never needs a port open to the internet,
// and a receipt that arrives while the bot is offline is handled when it starts.
//
// Env: TEBEX_WEBHOOK_SECRET        - Tebex -> Developers -> Webhooks -> Endpoints -> secret
//      DISCORD_RECEIPT_WEBHOOK_URL - from the bot: /store webhook (staff-only reply)
import crypto from 'crypto';
import { allStoreItems } from './products';
import { SITE_URL } from './site';

// Tebex only sends webhooks from these addresses.
export const TEBEX_WEBHOOK_IPS = ['18.209.80.3', '54.87.231.232'];

export function webhookSecret() {
  return String(process.env.TEBEX_WEBHOOK_SECRET || '').trim();
}

export function receiptWebhookUrl() {
  const url = String(process.env.DISCORD_RECEIPT_WEBHOOK_URL || '').trim();
  return /^https:\/\/(?:canary\.|ptb\.)?discord(?:app)?\.com\/api\/webhooks\/\d+\/[\w-]+$/.test(url) ? url : '';
}

export function receiptsReady() {
  return Boolean(webhookSecret() && receiptWebhookUrl());
}

// X-Signature = HMAC-SHA256(key: webhook secret, message: hex SHA-256 of the raw body), hex.
export function validSignature(rawBody, signature, secret = webhookSecret()) {
  if (!secret || !signature) return false;
  const bodyHash = crypto.createHash('sha256').update(rawBody, 'utf8').digest('hex');
  const expected = crypto.createHmac('sha256', secret).update(bodyHash).digest('hex');
  const a = Buffer.from(String(signature).trim().toLowerCase());
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// The checkout saves discord_id in the basket's custom data when the buyer logged in
// with Discord. Tebex sends that custom data back with the webhook; look for it anywhere.
export function findDiscordId(value, depth = 0) {
  if (!value || typeof value !== 'object' || depth > 6) return null;
  for (const [key, v] of Object.entries(value)) {
    if (/^discord_?id$/i.test(key) && /^\d{15,22}$/.test(String(v))) return String(v);
  }
  for (const v of Object.values(value)) {
    const found = findDiscordId(v, depth + 1);
    if (found) return found;
  }
  return null;
}

function findDiscordName(value, depth = 0) {
  if (!value || typeof value !== 'object' || depth > 6) return null;
  if (typeof value.discord_username === 'string') return value.discord_username;
  for (const v of Object.values(value)) {
    const found = findDiscordName(v, depth + 1);
    if (found) return found;
  }
  return null;
}

const clip = (s, n) => String(s ?? '').slice(0, n);
const money = v => {
  const n = Number(v);
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : null;
};

// Tebex webhook type -> what the bot shows. Purchases DM the buyer; the rest are staff alerts.
export const RECEIPT_KINDS = {
  'payment.completed': 'purchase',
  'payment.refunded': 'refund',
  'payment.dispute.opened': 'dispute_opened',
  'payment.dispute.won': 'dispute_won',
  'payment.dispute.lost': 'dispute_lost',
  'payment.dispute.closed': 'dispute_closed'
};

const KIND_TITLES = {
  purchase: 'Store purchase',
  refund: 'Store refund',
  dispute_opened: 'Chargeback opened',
  dispute_won: 'Chargeback won',
  dispute_lost: 'Chargeback lost',
  dispute_closed: 'Chargeback closed'
};

// catalog: getResolvedCatalog() rows (has tebex_package_id). Falls back to the static list.
export function buildReceipt(subject, catalog = [], kind = 'purchase') {
  const s = subject || {};
  const byPackage = id => catalog.find(p => p.tebex_package_id && String(p.tebex_package_id) === String(id));
  const byName = name => allStoreItems.find(p => p.title.toLowerCase() === String(name || '').toLowerCase());
  const abs = img => (img ? (/^https?:/.test(img) ? img : SITE_URL.replace(/\/+$/, '') + img) : null);

  const items = (Array.isArray(s.products) ? s.products : []).slice(0, 15).map(p => {
    const local = byPackage(p.id) || byName(p.name);
    return {
      t: clip(local?.title || p.name || 'Package', 80),
      q: Math.max(1, Number(p.quantity) || 1),
      p: money(p.paid_price?.amount ?? p.base_price?.amount),
      img: abs(local?.image),
      d: clip(local?.delivery || '', 140),
      c: clip(local?.category || '', 30)
    };
  });

  const paid = s.price_paid || s.price || {};
  return {
    v: 1,
    kind: KIND_TITLES[kind] ? kind : 'purchase',
    tx: clip(s.transaction_id, 64),
    at: s.created_at ? Date.parse(s.created_at) || Date.now() : Date.now(),
    discordId: findDiscordId(s),
    discordName: clip(findDiscordName(s) || '', 64) || null,
    fivem: clip(s.customer?.username?.username || '', 64) || null,
    items,
    total: money(paid.amount),
    cur: clip(paid.currency || s.price?.currency || 'USD', 8),
    method: clip(s.payment_method?.name || '', 40) || null,
    coupons: (Array.isArray(s.coupons) ? s.coupons : []).slice(0, 3).map(c => clip(c.code || c.name || '', 30)).filter(Boolean)
  };
}

// Posts the receipt to the staff channel. The bot reads the JSON block, so keep the format.
export async function postReceipt(receipt, url = receiptWebhookUrl()) {
  if (!url) throw new Error('DISCORD_RECEIPT_WEBHOOK_URL is not set');
  const json = JSON.stringify(receipt);
  if (json.length > 3900) throw new Error('Receipt too large');
  const lines = receipt.items.map(i => `${i.q}× ${i.t}`).join(', ');
  const res = await fetch(url + '?wait=true', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      username: 'PMv2 Store',
      allowed_mentions: { parse: [] },
      embeds: [{
        title: `${KIND_TITLES[receipt.kind] || 'Store purchase'} ${receipt.tx}`,
        description: '```json\n' + json + '\n```',
        color: receipt.kind === 'purchase' ? 0xf5c542 : 0xe74c3c,
        footer: { text: clip(lines, 2000) || 'Purchase' }
      }]
    }),
    cache: 'no-store',
    signal: AbortSignal.timeout(10000)
  });
  if (!res.ok) throw new Error(`Discord webhook HTTP ${res.status}`);
  return true;
}
