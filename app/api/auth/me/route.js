// Who's shopping right now (from the signed cookie) + their Misfit Coin balance.
import { NextResponse } from 'next/server';
import { readCustomer, customerLoginReady } from '../../../../lib/customerSession';
import { dbReady, query } from '../../../../lib/db';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(req) {
  const user = readCustomer(req);
  let coins = null;
  if (user && dbReady()) {
    try {
      const rows = await query(
        `SELECT COALESCE(w.balance, 0) AS coins
         FROM pmv2_store_customers c LEFT JOIN pmv2_store_wallets w ON w.customer_id = c.id
         WHERE c.discord_id = ?`,
        [user.id]
      );
      coins = rows[0] ? Number(rows[0].coins) : 0;
    } catch { coins = null; }
  }
  return NextResponse.json(
    { loginAvailable: customerLoginReady(), user: user ? { id: user.id, username: user.username, avatarUrl: user.avatarUrl, coins } : null },
    { headers: { 'Cache-Control': 'no-store' } }
  );
}
