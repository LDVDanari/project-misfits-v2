// Step 1 of "Log in with Discord": send the shopper to Discord's consent page.
import crypto from 'crypto';
import { NextResponse } from 'next/server';
import { publicOrigin } from '../../../../../lib/origin';
import { customerLoginReady, OAUTH_STATE_COOKIE } from '../../../../../lib/customerSession';
import { redirectUri, safeNext } from '../../../../../lib/discordAuth';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(req) {
  const origin = publicOrigin(req);
  const next = safeNext(new URL(req.url).searchParams.get('next'));
  if (!customerLoginReady()) return NextResponse.redirect(origin + next + (next.includes('?') ? '&' : '?') + 'login_error=not_configured');

  const state = crypto.randomBytes(24).toString('base64url');
  const url = new URL('https://discord.com/oauth2/authorize');
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('client_id', process.env.DISCORD_CLIENT_ID);
  url.searchParams.set('scope', 'identify');
  url.searchParams.set('state', state);
  url.searchParams.set('redirect_uri', redirectUri(req));
  url.searchParams.set('prompt', 'none');

  const res = NextResponse.redirect(url.toString());
  res.cookies.set(OAUTH_STATE_COOKIE, state + '|' + next, { httpOnly: true, secure: true, sameSite: 'lax', path: '/', maxAge: 600 });
  return res;
}
