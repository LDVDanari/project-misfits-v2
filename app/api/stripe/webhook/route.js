import { NextResponse } from 'next/server';
import { verifyStripeSignature } from '../../../../lib/stripeServer';
import { dbReady } from '../../../../lib/db';
import { handleStripeEvent } from '../../../../lib/fulfillment';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Stripe events to enable for this endpoint:
//   checkout.session.completed, checkout.session.async_payment_succeeded,
//   charge.refunded, charge.dispute.created, charge.dispute.closed
export async function POST(req) {
  const raw = await req.text();
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!secret) return NextResponse.json({ error: 'Webhook not configured' }, { status: 503 });
  if (!verifyStripeSignature(raw, req.headers.get('stripe-signature'), secret)) {
    return NextResponse.json({ error: 'Invalid signature' }, { status: 400 });
  }
  // Without the database we can't record anything; a non-200 makes Stripe retry later.
  if (!dbReady()) return NextResponse.json({ error: 'Store database not configured' }, { status: 503 });

  let event;
  try { event = JSON.parse(raw); } catch { return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 }); }

  try {
    const result = await handleStripeEvent(event);
    return NextResponse.json({ received: true, ...result });
  } catch (e) {
    console.error('PMv2 webhook failed for', event?.type, event?.id, '-', e.message);
    return NextResponse.json({ error: 'Processing failed, Stripe will retry' }, { status: 500 });
  }
}
