import { NextResponse } from 'next/server';
import { getTebexMatchReport } from '../../../../lib/catalogServer';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Owner dashboard: which site products are linked to which Tebex packages.
// Prices, availability, coupons, refunds and payouts are managed in the Tebex control panel.
export async function GET() {
  try {
    return NextResponse.json(await getTebexMatchReport());
  } catch (e) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
