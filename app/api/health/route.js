import { stripeReady } from '../../../lib/stripeServer';
import { dbReady } from '../../../lib/db';
import { customerLoginReady } from '../../../lib/customerSession';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

// Shows which store settings the running app can see (names only, never values),
// so setup problems in Coolify are easy to spot.
export async function GET() {
  const has = k => Boolean(String(process.env[k] || '').trim());
  const secretLen = String(process.env.CUSTOMER_SESSION_SECRET || '').trim().length;
  const missing = [];
  if (!has('STRIPE_SECRET_KEY')) missing.push('STRIPE_SECRET_KEY');
  if (!dbReady()) missing.push(has('DATABASE_URL') ? 'DATABASE_URL' : 'DB_HOST / DB_USER / DB_NAME (or DATABASE_URL)');
  if (!has('DISCORD_CLIENT_ID')) missing.push('DISCORD_CLIENT_ID');
  if (!has('DISCORD_CLIENT_SECRET')) missing.push('DISCORD_CLIENT_SECRET');
  if (secretLen < 32) missing.push(secretLen ? 'CUSTOMER_SESSION_SECRET (too short, needs 32+ characters)' : 'CUSTOMER_SESSION_SECRET');
  return Response.json({
    ok: true,
    service: 'project-misfits-v2-web',
    version: '2.1.0',
    store: {
      stripe: stripeReady(),
      database: dbReady(),
      discordLogin: customerLoginReady(),
      orderLogs: has('STORE_ORDERS_WEBHOOK_URL'),
      checkoutReady: stripeReady() && dbReady() && customerLoginReady(),
      missing
    }
  }, { headers: { 'Cache-Control': 'no-store' } });
}
