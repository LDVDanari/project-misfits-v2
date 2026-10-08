// Signed, HTTP-only cookie that remembers which Discord account is shopping.
// Only holds public Discord info (id, name, avatar) - never tokens or passwords.
import crypto from 'crypto';

export const CUSTOMER_COOKIE = 'pmv2_customer';
export const OAUTH_STATE_COOKIE = 'pmv2_oauth_state';
const MAX_AGE = 30 * 24 * 60 * 60; // 30 days

function secret() {
  const s = String(process.env.CUSTOMER_SESSION_SECRET || '').trim();
  return s.length >= 32 ? s : '';
}

export function customerLoginReady() {
  return Boolean(process.env.DISCORD_CLIENT_ID && process.env.DISCORD_CLIENT_SECRET && secret());
}

function sign(payload) {
  return crypto.createHmac('sha256', secret()).update(payload).digest('base64url');
}

export function createCustomerToken(user) {
  const body = {
    id: String(user.id),
    u: String(user.username || '').slice(0, 64),
    a: user.avatar ? String(user.avatar).slice(0, 128) : null,
    exp: Date.now() + MAX_AGE * 1000
  };
  const payload = Buffer.from(JSON.stringify(body)).toString('base64url');
  return payload + '.' + sign(payload);
}

export function readCustomer(req) {
  if (!secret()) return null;
  const token = req.cookies?.get?.(CUSTOMER_COOKIE)?.value || '';
  const dot = token.lastIndexOf('.');
  if (dot < 1) return null;
  const payload = token.slice(0, dot), sig = token.slice(dot + 1);
  const expected = sign(payload);
  const a = Buffer.from(sig), b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    if (!data?.id || !/^\d{15,22}$/.test(data.id) || Date.now() > Number(data.exp)) return null;
    return {
      id: data.id,
      username: data.u || 'Discord user',
      avatar: data.a || null,
      avatarUrl: data.a
        ? `https://cdn.discordapp.com/avatars/${data.id}/${data.a}.png?size=64`
        : `https://cdn.discordapp.com/embed/avatars/${Number((BigInt(data.id) >> 22n) % 6n)}.png`
    };
  } catch {
    return null;
  }
}

export const customerCookieOptions = {
  httpOnly: true,
  secure: true,
  sameSite: 'lax',
  path: '/',
  maxAge: MAX_AGE
};
