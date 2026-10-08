import { publicOrigin } from './origin';

// Only allow redirects back to our own pages after login.
export function safeNext(value) {
  const v = String(value || '');
  return v.startsWith('/') && !v.startsWith('//') && !v.includes('\\') ? v.slice(0, 200) : '/checkout';
}

export function redirectUri(req) {
  return (process.env.DISCORD_REDIRECT_URI || '').trim() || publicOrigin(req) + '/api/auth/discord/callback';
}
