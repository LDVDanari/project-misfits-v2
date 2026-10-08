// Turns paid Stripe checkouts into store records the city can act on.
//
//   checkout.session.completed / async_payment_succeeded
//     -> order + items
//     -> coins: added to the buyer's wallet right away (+ an in-city "coins arrived" message)
//     -> priority: active entitlement
//     -> packages: entitlement waiting on staff setup
//   charge.refunded       -> full refund takes coins back and revokes entitlements
//   charge.dispute.created -> order flagged for the owner
//
// Every step is safe to repeat: Stripe may send the same event several times.
import crypto from 'crypto';
import { getProduct } from './products';
import { stripeRequest } from './stripeServer';
import { query, withTransaction, isDuplicate } from './db';
import { notifyStaff, money } from './staffNotify';

const REF_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I so codes are easy to read out

export function newOrderRef() {
  let ref = 'PM-';
  for (const b of crypto.randomBytes(6)) ref += REF_CHARS[b % REF_CHARS.length];
  return ref;
}

export function itemKind(slug) {
  const p = getProduct(slug);
  if (!p) return null;
  if (p.category === 'MISFIT COINS') return 'coins';
  if (p.category === 'PRIORITY') return 'priority';
  return 'package';
}
export const coinsEach = slug => Number((/^(\d+)-coins$/.exec(slug) || [])[1] || 0);
const tierOf = slug => (/^(bronze|silver|gold)-priority$/.exec(slug) || [])[1] || null;

async function audit(conn, actor, action, targetType, targetId, details) {
  await conn.execute(
    'INSERT INTO pmv2_store_audit_log (actor, action, target_type, target_id, details) VALUES (?, ?, ?, ?, ?)',
    [actor, action, targetType, targetId == null ? null : String(targetId), details ? JSON.stringify(details) : null]
  );
}

// ------------------------------------------------------------
// Webhook entry point
// ------------------------------------------------------------
export async function handleStripeEvent(event) {
  const type = event?.type;
  const obj = event?.data?.object || {};
  const handlers = {
    'checkout.session.completed': () => fulfillCheckoutSession(obj.id),
    'checkout.session.async_payment_succeeded': () => fulfillCheckoutSession(obj.id),
    'charge.refunded': () => handleRefund(obj),
    'charge.dispute.created': () => handleDispute(obj)
  };
  const handler = handlers[type];
  if (!handler) return { ignored: true };
  if (!/^evt_[A-Za-z0-9_]+$/.test(String(event.id || ''))) throw new Error('Invalid event id');

  const ins = await query(
    'INSERT IGNORE INTO pmv2_store_webhook_events (stripe_event_id, event_type, stripe_object_id) VALUES (?, ?, ?)',
    [event.id, type, obj.id || null]
  );
  if (!ins.affectedRows) {
    const [row] = await query('SELECT status FROM pmv2_store_webhook_events WHERE stripe_event_id = ?', [event.id]);
    if (row?.status === 'processed') return { duplicate: true };
    await query("UPDATE pmv2_store_webhook_events SET status = 'processing', error = NULL WHERE stripe_event_id = ?", [event.id]);
  }

  try {
    const result = await handler();
    await query(
      "UPDATE pmv2_store_webhook_events SET status = 'processed', processed_at = CURRENT_TIMESTAMP(3), error = NULL WHERE stripe_event_id = ?",
      [event.id]
    );
    return result || { ok: true };
  } catch (e) {
    await query("UPDATE pmv2_store_webhook_events SET status = 'failed', error = ? WHERE stripe_event_id = ?", [String(e.message || e).slice(0, 1000), event.id]).catch(() => {});
    throw e;
  }
}

// ------------------------------------------------------------
// Paid checkout
// ------------------------------------------------------------
async function loadSessionItems(session) {
  const list = await stripeRequest(
    '/checkout/sessions/' + encodeURIComponent(session.id) + '/line_items?limit=100&expand[]=data.price.product'
  );
  return (list.data || []).map((line, i) => {
    let slug = line.price?.product?.metadata?.pmv2_slug || '';
    if (!slug) {
      const raw = session.metadata?.['item_' + i] || '';
      const idx = raw.lastIndexOf(':');
      slug = idx > -1 ? raw.slice(0, idx) : raw;
    }
    const product = getProduct(slug);
    if (!product) throw new Error(`Unknown store item "${slug}" on ${session.id}`);
    const qty = Math.max(1, Number(line.quantity) || 1);
    const unit = Number(line.price?.unit_amount ?? Math.round((line.amount_subtotal || 0) / qty));
    return { slug, qty, unit_amount: unit, title: product.title, kind: itemKind(slug) };
  });
}

export async function fulfillCheckoutSession(sessionId) {
  if (!/^cs_[A-Za-z0-9_]+$/.test(String(sessionId || ''))) throw new Error('Invalid checkout session id');

  // Always re-read the session from Stripe instead of trusting the event body.
  const session = await stripeRequest('/checkout/sessions/' + encodeURIComponent(sessionId));
  if (!['paid', 'no_payment_required'].includes(session.payment_status)) return { pending: true };

  const discordId = String(session.metadata?.discord_id || session.client_reference_id || '');
  if (!/^\d{15,22}$/.test(discordId)) {
    // Paid without a Discord login (old checkout or a manual Stripe link). Staff handle it by hand.
    await withTransaction(conn => audit(conn, 'system', 'order.unlinked', 'stripe_session', session.id, { amount_total: session.amount_total }));
    await notifyStaff({
      title: 'Paid order without a Discord account',
      color: 0xffb25c,
      lines: [`Stripe checkout \`${session.id}\` (${money(session.amount_total, session.currency)}) was paid but isn't linked to a Discord account.`, 'Match it to the buyer by hand from the owner dashboard.']
    });
    return { unlinked: true };
  }

  const items = await loadSessionItems(session);
  const email = session.customer_details?.email || session.customer_email || null;
  const username = session.metadata?.discord_username || null;
  const paymentIntent = typeof session.payment_intent === 'string' ? session.payment_intent : session.payment_intent?.id || null;

  const result = await withTransaction(async conn => {
    await conn.execute(
      `INSERT INTO pmv2_store_customers (discord_id, discord_username, email) VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE discord_username = COALESCE(?, discord_username), email = COALESCE(?, email)`,
      [discordId, username, email, username, email]
    );
    const [[customer]] = await conn.execute('SELECT id FROM pmv2_store_customers WHERE discord_id = ? FOR UPDATE', [discordId]);

    const [[existing]] = await conn.execute('SELECT id, order_ref FROM pmv2_store_orders WHERE stripe_session_id = ? FOR UPDATE', [session.id]);
    if (existing) return { alreadyFulfilled: true, orderRef: existing.order_ref };

    let orderId = null, orderRef = null;
    for (let attempt = 0; attempt < 6 && !orderId; attempt++) {
      orderRef = newOrderRef();
      try {
        const [r] = await conn.execute(
          `INSERT INTO pmv2_store_orders
             (order_ref, stripe_session_id, stripe_payment_intent, customer_id, discord_id, email, status,
              currency, amount_subtotal, amount_discount, amount_tax, amount_total, paid_at)
           VALUES (?, ?, ?, ?, ?, ?, 'paid', ?, ?, ?, ?, ?, CURRENT_TIMESTAMP(3))`,
          [
            orderRef, session.id, paymentIntent, customer.id, discordId, email,
            String(session.currency || 'usd').slice(0, 3),
            session.amount_subtotal || 0,
            session.total_details?.amount_discount || 0,
            session.total_details?.amount_tax || 0,
            session.amount_total || 0
          ]
        );
        orderId = r.insertId;
      } catch (e) {
        if (isDuplicate(e) && /order_ref/.test(e.message)) continue; // one-in-a-billion code clash, pick another
        throw e;
      }
    }
    if (!orderId) throw new Error('Could not create an order code');

    let coinsAdded = 0, needsSetup = false;
    for (const it of items) {
      const each = it.kind === 'coins' ? coinsEach(it.slug) : null;
      const done = it.kind !== 'package';
      const [r] = await conn.execute(
        `INSERT INTO pmv2_store_order_items
           (order_id, product_slug, product_title, kind, quantity, unit_amount, coins_each, fulfillment_status, fulfilled_by, fulfilled_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ${done ? 'CURRENT_TIMESTAMP(3)' : 'NULL'})`,
        [orderId, it.slug, it.title, it.kind, it.qty, it.unit_amount, each, done ? 'delivered' : 'pending', done ? 'system' : null]
      );
      const itemId = r.insertId;

      if (it.kind === 'coins') {
        const amount = each * it.qty;
        await conn.execute(
          'INSERT INTO pmv2_store_wallets (customer_id, balance, lifetime_purchased) VALUES (?, 0, 0) ON DUPLICATE KEY UPDATE customer_id = customer_id',
          [customer.id]
        );
        const [[wallet]] = await conn.execute('SELECT balance FROM pmv2_store_wallets WHERE customer_id = ? FOR UPDATE', [customer.id]);
        const after = Number(wallet.balance) + amount;
        await conn.execute(
          `INSERT INTO pmv2_store_coin_ledger (customer_id, delta, reason, balance_after, order_item_id, reference, idempotency_key, actor)
           VALUES (?, ?, 'purchase', ?, ?, ?, ?, 'system')`,
          [customer.id, amount, after, itemId, orderRef, 'purchase:' + itemId]
        );
        await conn.execute('UPDATE pmv2_store_wallets SET balance = ?, lifetime_purchased = lifetime_purchased + ? WHERE customer_id = ?', [after, amount, customer.id]);
        await conn.execute(
          `INSERT INTO pmv2_store_deliveries (customer_id, discord_id, order_item_id, action, payload) VALUES (?, ?, ?, 'notify', ?)`,
          [customer.id, discordId, itemId, JSON.stringify({ message: `${amount} Misfit Coins were added to your account. Order ${orderRef}.`, coins: amount, order_ref: orderRef })]
        );
        coinsAdded += amount;
      } else if (it.kind === 'priority') {
        await conn.execute(
          `INSERT INTO pmv2_store_entitlements (customer_id, discord_id, order_item_id, type, product_slug, tier, status, details)
           VALUES (?, ?, ?, 'priority', ?, ?, 'active', ?)`,
          [customer.id, discordId, itemId, it.slug, tierOf(it.slug), JSON.stringify({ order_ref: orderRef })]
        );
        await conn.execute(
          `INSERT INTO pmv2_store_deliveries (customer_id, discord_id, order_item_id, action, payload) VALUES (?, ?, ?, 'notify', ?)`,
          [customer.id, discordId, itemId, JSON.stringify({ message: `${it.title} is now active on your account. Order ${orderRef}.`, order_ref: orderRef })]
        );
      } else {
        needsSetup = true;
        for (let u = 0; u < it.qty; u++) {
          await conn.execute(
            `INSERT INTO pmv2_store_entitlements (customer_id, discord_id, order_item_id, type, product_slug, status, details)
             VALUES (?, ?, ?, 'package', ?, 'pending_setup', ?)`,
            [customer.id, discordId, itemId, it.slug, JSON.stringify({ order_ref: orderRef })]
          );
        }
      }
    }

    await audit(conn, 'system', 'order.paid', 'order', orderRef, {
      stripe_session_id: session.id, amount_total: session.amount_total, items: items.map(i => `${i.slug}:${i.qty}`)
    });
    return { orderRef, coinsAdded, needsSetup };
  });

  if (!result.alreadyFulfilled) {
    // Show the order code and status in Stripe / the owner dashboard too.
    stripeRequest('/checkout/sessions/' + encodeURIComponent(session.id), {
      method: 'POST',
      body: { 'metadata[pmv2_order_ref]': result.orderRef, 'metadata[fulfillment_status]': result.needsSetup ? 'new' : 'fulfilled' }
    }).catch(e => console.error('PMv2 could not tag Stripe session:', e.message));

    await notifyStaff({
      title: `New order ${result.orderRef}`,
      color: result.needsSetup ? 0xffb25c : 0xa200ec,
      lines: [
        `Buyer: <@${discordId}>${username ? ` (${username})` : ''}`,
        `Total: **${money(session.amount_total, session.currency)}**`,
        ...items.map(i => `- ${i.qty}x ${i.title}`),
        result.needsSetup ? '\n**Needs staff setup.** Mark it done with `/storedone ' + result.orderRef + '` in the city or from the owner dashboard.' : '\nDelivered automatically.'
      ]
    });
  }
  return result;
}

// ------------------------------------------------------------
// Refunds and disputes
// ------------------------------------------------------------
const piOf = obj => (typeof obj.payment_intent === 'string' ? obj.payment_intent : obj.payment_intent?.id) || null;

export async function handleRefund(charge) {
  const pi = piOf(charge);
  if (!pi) return { ignored: true };

  const result = await withTransaction(async conn => {
    const [[order]] = await conn.execute('SELECT * FROM pmv2_store_orders WHERE stripe_payment_intent = ? FOR UPDATE', [pi]);
    if (!order) return { unknown: true };
    if (order.status === 'refunded') return { already: true };

    const refunded = Number(charge.amount_refunded || 0);
    const full = charge.refunded === true || refunded >= Number(order.amount_total);
    await conn.execute(
      'UPDATE pmv2_store_orders SET status = ?, amount_refunded = ?, refunded_at = CURRENT_TIMESTAMP(3) WHERE id = ?',
      [full ? 'refunded' : 'partially_refunded', refunded, order.id]
    );

    let coinsRemoved = 0;
    if (full) {
      const [items] = await conn.execute('SELECT * FROM pmv2_store_order_items WHERE order_id = ? FOR UPDATE', [order.id]);
      for (const it of items) {
        if (it.kind !== 'coins' || it.fulfillment_status === 'revoked') continue;
        const amount = Number(it.coins_each) * Number(it.quantity);
        const [[wallet]] = await conn.execute('SELECT balance FROM pmv2_store_wallets WHERE customer_id = ? FOR UPDATE', [order.customer_id]);
        const after = Number(wallet?.balance || 0) - amount;
        try {
          await conn.execute(
            `INSERT INTO pmv2_store_coin_ledger (customer_id, delta, reason, balance_after, order_item_id, reference, idempotency_key, actor)
             VALUES (?, ?, 'refund', ?, ?, ?, ?, 'system')`,
            [order.customer_id, -amount, after, it.id, order.order_ref, 'refund:' + it.id]
          );
        } catch (e) {
          if (isDuplicate(e)) continue; // already taken back
          throw e;
        }
        await conn.execute('UPDATE pmv2_store_wallets SET balance = ? WHERE customer_id = ?', [after, order.customer_id]);
        coinsRemoved += amount;
      }
      await conn.execute(
        `UPDATE pmv2_store_entitlements SET status = 'revoked', revoked_reason = 'Order refunded'
         WHERE status <> 'revoked' AND order_item_id IN (SELECT id FROM pmv2_store_order_items WHERE order_id = ?)`,
        [order.id]
      );
      await conn.execute(
        `UPDATE pmv2_store_deliveries SET status = 'canceled'
         WHERE status IN ('pending', 'claimed') AND order_item_id IN (SELECT id FROM pmv2_store_order_items WHERE order_id = ?)`,
        [order.id]
      );
      await conn.execute("UPDATE pmv2_store_order_items SET fulfillment_status = 'revoked' WHERE order_id = ?", [order.id]);
    }
    await audit(conn, 'system', full ? 'order.refunded' : 'order.partially_refunded', 'order', order.order_ref, { amount_refunded: refunded, coins_removed: coinsRemoved });
    return { orderRef: order.order_ref, discordId: order.discord_id, full, refunded, currency: order.currency, coinsRemoved };
  });

  if (result.orderRef) {
    await notifyStaff({
      title: `${result.full ? 'Refunded' : 'Partly refunded'}: ${result.orderRef}`,
      color: 0xe74c3c,
      lines: [
        `Buyer: <@${result.discordId}>`,
        `Refunded: **${money(result.refunded, result.currency)}**`,
        result.full
          ? `Coins taken back: ${result.coinsRemoved}. Packages and priority on this order were revoked.`
          : 'Partial refund: nothing was taken back automatically. Adjust coins or packages by hand if needed.'
      ]
    });
  }
  return result;
}

export async function handleDispute(dispute) {
  const pi = piOf(dispute);
  if (!pi) return { ignored: true };
  const result = await withTransaction(async conn => {
    const [[order]] = await conn.execute('SELECT id, order_ref, discord_id FROM pmv2_store_orders WHERE stripe_payment_intent = ? FOR UPDATE', [pi]);
    if (!order) return { unknown: true };
    await conn.execute("UPDATE pmv2_store_orders SET status = 'disputed' WHERE id = ?", [order.id]);
    await audit(conn, 'system', 'order.disputed', 'order', order.order_ref, { reason: dispute.reason || null, amount: dispute.amount || null });
    return { orderRef: order.order_ref, discordId: order.discord_id };
  });
  if (result.orderRef) {
    await notifyStaff({
      title: `Chargeback opened: ${result.orderRef}`,
      color: 0xe74c3c,
      lines: [`Buyer: <@${result.discordId}>`, `Reason: ${dispute.reason || 'not given'}`, 'Respond in the Stripe dashboard. Nothing was revoked automatically.']
    });
  }
  return result;
}

// ------------------------------------------------------------
// Staff / owner helpers
// ------------------------------------------------------------

// Owner marked an order fulfilled: finish package setup in the database too.
export async function markOrderFulfilled(sessionId, actor = 'owner') {
  return withTransaction(async conn => {
    const [[order]] = await conn.execute('SELECT id, order_ref FROM pmv2_store_orders WHERE stripe_session_id = ? FOR UPDATE', [sessionId]);
    if (!order) return { unknown: true };
    await conn.execute(
      `UPDATE pmv2_store_order_items SET fulfillment_status = 'fulfilled', fulfilled_by = ?, fulfilled_at = CURRENT_TIMESTAMP(3)
       WHERE order_id = ? AND kind = 'package' AND fulfillment_status IN ('pending', 'processing')`,
      [actor, order.id]
    );
    await conn.execute(
      `UPDATE pmv2_store_entitlements SET status = 'active'
       WHERE status = 'pending_setup' AND order_item_id IN (SELECT id FROM pmv2_store_order_items WHERE order_id = ?)`,
      [order.id]
    );
    await audit(conn, actor, 'order.fulfilled', 'order', order.order_ref, null);
    return { orderRef: order.order_ref };
  });
}

export async function orderRefForSession(sessionId) {
  const rows = await query('SELECT order_ref, status FROM pmv2_store_orders WHERE stripe_session_id = ?', [sessionId]);
  return rows[0] || null;
}
