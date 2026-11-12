import { NextResponse } from 'next/server';
import { clientIp } from '../../../../lib/tebex';
import { getResolvedCatalog } from '../../../../lib/catalogServer';
import { TEBEX_WEBHOOK_IPS, RECEIPT_KINDS, webhookSecret, validSignature, buildReceipt, postReceipt, receiptWebhookUrl } from '../../../../lib/receipts';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Tebex -> Developers -> Webhooks -> Endpoints: https://projectmisfitsrp.com/api/tebex/webhook
// Subscribe to "payment.completed", "payment.refunded" and the "payment.dispute.*" events.
// Only signed requests from Tebex are accepted.
export async function POST(req) {
  const notFound = () => new NextResponse('Not Found', { status: 404 });
  if (!webhookSecret()) return notFound();

  // Tebex suggests ignoring anything not from its two addresses. Set
  // TEBEX_WEBHOOK_IP_CHECK=off only if a proxy hides the real address.
  if (String(process.env.TEBEX_WEBHOOK_IP_CHECK || '').toLowerCase() !== 'off') {
    const ip = clientIp(req);
    if (!ip || !TEBEX_WEBHOOK_IPS.includes(ip)) return notFound();
  }

  const raw = await req.text();
  if (raw.length > 200_000 || !validSignature(raw, req.headers.get('x-signature'))) {
    return NextResponse.json({ error: 'Invalid signature' }, { status: 403 });
  }

  let event;
  try { event = JSON.parse(raw); } catch { return NextResponse.json({ error: 'Bad JSON' }, { status: 400 }); }

  if (event?.type === 'validation.webhook') return NextResponse.json({ id: event.id });
  const kind = RECEIPT_KINDS[event?.type];
  if (!kind) return NextResponse.json({ ok: true, ignored: event?.type || null });

  if (!receiptWebhookUrl()) {
    console.error('[tebex webhook] DISCORD_RECEIPT_WEBHOOK_URL is not set - receipt not sent');
    return NextResponse.json({ ok: true, receipt: 'not configured' });
  }

  try {
    const catalog = await getResolvedCatalog({ ip: null }).catch(() => []);
    const receipt = buildReceipt(event.subject, catalog, kind);
    if (!receipt.tx) return NextResponse.json({ ok: true, receipt: 'no transaction id' });
    await postReceipt(receipt);
    return NextResponse.json({ ok: true });
  } catch (e) {
    // A 5xx makes Tebex retry later; the bot ignores a receipt it already handled.
    console.error('[tebex webhook]', e.message);
    return NextResponse.json({ error: 'Receipt failed' }, { status: 502 });
  }
}
