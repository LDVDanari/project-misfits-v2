// Keeps the store database in step with Stripe without needing Stripe webhooks.
//
// Every couple of minutes it asks Stripe for:
//   - paid checkouts from the last 3 days that aren't recorded yet (buyer closed the tab
//     before the confirmation page loaded)
//   - refunds from the last 3 days
//   - chargebacks from the last 120 days (they can take weeks to settle)
// and runs each through the same safe-to-repeat code the webhook uses.
// If you do also set up the Stripe webhook, both can run side by side.
import { stripeReady, stripeRequest } from './stripeServer';
import { dbReady, query } from './db';
import { handleStripeEvent } from './fulfillment';

let started = false, running = false;
const now = () => Math.floor(Date.now() / 1000);
const DAY = 86400;

export function startStoreSync() {
  if (started) return;
  started = true;
  const every = Math.max(60, Number(process.env.STORE_SYNC_SECONDS || 120)) * 1000;
  const first = setTimeout(syncStoreNow, 20000);
  const loop = setInterval(syncStoreNow, every);
  first.unref?.();
  loop.unref?.();
}

export async function syncStoreNow() {
  if (running || !stripeReady() || !dbReady()) return { skipped: true };
  running = true;
  const result = { checkouts: 0, refunds: 0, disputes: 0 };
  try {
    result.checkouts = await syncCheckouts();
    result.refunds = await syncRefunds();
    result.disputes = await syncDisputes();
  } catch (e) {
    console.error('PMv2 store sync failed:', e.message);
    result.error = e.message;
  } finally {
    running = false;
  }
  return result;
}

async function listAll(path, maxPages = 5) {
  const out = [];
  let after = null;
  for (let page = 0; page < maxPages; page++) {
    const r = await stripeRequest(path + (path.includes('?') ? '&' : '?') + 'limit=100' + (after ? '&starting_after=' + encodeURIComponent(after) : ''));
    const data = r.data || [];
    out.push(...data);
    if (!r.has_more || !data.length) break;
    after = data[data.length - 1].id;
  }
  return out;
}

const marks = n => Array(n).fill('?').join(',');

async function alreadyProcessed(eventIds) {
  if (!eventIds.length) return new Set();
  const rows = await query(
    `SELECT stripe_event_id FROM pmv2_store_webhook_events WHERE status = 'processed' AND stripe_event_id IN (${marks(eventIds.length)})`,
    eventIds
  );
  return new Set(rows.map(r => r.stripe_event_id));
}

async function run(event) {
  try {
    const r = await handleStripeEvent(event);
    return r && !r.duplicate ? 1 : 0;
  } catch (e) {
    console.error('PMv2 store sync could not process', event.id, '-', e.message);
    return 0;
  }
}

async function syncCheckouts() {
  const sessions = await listAll(`/checkout/sessions?status=complete&created[gte]=${now() - 3 * DAY}`);
  const paid = sessions.filter(s => ['paid', 'no_payment_required'].includes(s.payment_status));
  if (!paid.length) return 0;
  const recorded = await query(
    `SELECT stripe_session_id FROM pmv2_store_orders WHERE stripe_session_id IN (${marks(paid.length)})`,
    paid.map(s => s.id)
  );
  const have = new Set(recorded.map(r => r.stripe_session_id));
  const todo = paid.filter(s => !have.has(s.id));
  const done = await alreadyProcessed(todo.map(s => 'evt_sync_' + s.id));
  let n = 0;
  for (const s of todo) {
    const id = 'evt_sync_' + s.id;
    if (!done.has(id)) n += await run({ id, type: 'checkout.session.completed', data: { object: { id: s.id } } });
  }
  return n;
}

async function syncRefunds() {
  const refunds = (await listAll(`/refunds?created[gte]=${now() - 3 * DAY}`)).filter(r => r.status === 'succeeded');
  const done = await alreadyProcessed(refunds.map(r => 'evt_sync_' + r.id));
  let n = 0;
  for (const r of refunds) {
    const id = 'evt_sync_' + r.id;
    if (done.has(id)) continue;
    const chargeId = typeof r.charge === 'string' ? r.charge : r.charge?.id;
    if (!chargeId) continue;
    const charge = await stripeRequest('/charges/' + encodeURIComponent(chargeId));
    n += await run({ id, type: 'charge.refunded', data: { object: charge } });
  }
  return n;
}

async function syncDisputes() {
  const disputes = await listAll(`/disputes?created[gte]=${now() - 120 * DAY}`);
  const ids = [];
  for (const d of disputes) {
    ids.push('evt_sync_' + d.id + '_open');
    if (d.status === 'won' || d.status === 'lost') ids.push('evt_sync_' + d.id + '_' + d.status);
  }
  const done = await alreadyProcessed(ids);
  let n = 0;
  for (const d of disputes) {
    const openId = 'evt_sync_' + d.id + '_open';
    if (!done.has(openId)) n += await run({ id: openId, type: 'charge.dispute.created', data: { object: d } });
    if (d.status === 'won' || d.status === 'lost') {
      const closeId = 'evt_sync_' + d.id + '_' + d.status;
      if (!done.has(closeId)) n += await run({ id: closeId, type: 'charge.dispute.closed', data: { object: d } });
    }
  }
  return n;
}
