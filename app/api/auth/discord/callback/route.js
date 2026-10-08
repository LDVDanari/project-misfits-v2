// Step 2 of "Log in with Discord": Discord sends the shopper back here with a code.
// We swap it for their public profile, remember them in a signed cookie and
// save them as a store customer. The Discord token is used once and thrown away.
import crypto from 'crypto';
import { NextResponse } from 'next/server';
import { publicOrigin } from '../../../../../lib/origin';
import { dbReady, query } from '../../../../../lib/db';
import {
  createCustomerToken, customerCookieOptions, customerLoginReady,
  CUSTOMER_COOKIE, OAUTH_STATE_COOKIE
} from '../../../../../lib/customerSession';
import { redirectUri, safeNext } from '../../../../../lib/discordAuth';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const DISCORD_API = () => (process.env.DISCORD_API_BASE || 'https://discord.com/api').replace(/\/$/, '');

function back(origin, next, error) {
  const url = origin + next + (error ? (next.includes('?') ? '&' : '?') + 'login_error=' + error : '');
  const res = NextResponse.redirect(url);
  res.cookies.set(OAUTH_STATE_COOKIE, '', { httpOnly: true, secure: true, sameSite: 'lax', path: '/', maxAge: 0 });
  return res;
}

export async function GET(req) {
  const origin = publicOrigin(req);
  const params = new URL(req.url).searchParams;
  const [savedState, savedNext] = String(req.cookies.get(OAUTH_STATE_COOKIE)?.value || '').split('|');
  const next = safeNext(savedNext);

  if (!customerLoginReady()) return back(origin, next, 'not_configured');
  if (params.get('error')) return back(origin, next, 'cancelled');

  const state = params.get('state') || '';
  const a = Buffer.from(state), b = Buffer.from(savedState || '');
  if (!state || a.length !== b.length || !crypto.timingSafeEqual(a, b)) return back(origin, next, 'expired');

  const code = params.get('code') || '';
  if (!code) return back(origin, next, 'failed');

  try {
    const tokenRes = await fetch(DISCORD_API() + '/oauth2/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: process.env.DISCORD_CLIENT_ID,
        client_secret: process.env.DISCORD_CLIENT_SECRET,
        grant_type: 'authorization_code',
        code,
        redirect_uri: redirectUri(req)
      }),
      cache: 'no-store'
    });
    const token = await tokenRes.json().catch(() => ({}));
    if (!tokenRes.ok || !token.access_token) throw new Error('Discord token exchange failed');

    const meRes = await fetch(DISCORD_API() + '/users/@me', {
      headers: { Authorization: 'Bearer ' + token.access_token },
      cache: 'no-store'
    });
    const me = await meRes.json().catch(() => ({}));
    if (!meRes.ok || !/^\d{15,22}$/.test(String(me.id || ''))) throw new Error('Discord profile lookup failed');

    const username = me.global_name || me.username || 'Discord user';
    if (dbReady()) {
      await query(
        `INSERT INTO pmv2_store_customers (discord_id, discord_username, discord_avatar)
         VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE discord_username = ?, discord_avatar = ?`,
        [me.id, username, me.avatar || null, username, me.avatar || null]
      );
    }

    const res = back(origin, next, null);
    res.cookies.set(CUSTOMER_COOKIE, createCustomerToken({ id: me.id, username, avatar: me.avatar }), customerCookieOptions);
    return res;
  } catch (e) {
    console.error('PMv2 Discord login failed:', e.message);
    return back(origin, next, 'failed');
  }
}
