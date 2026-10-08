// Public https origin of the site, safe behind Coolify's proxy.
export function publicOrigin(req) {
  const env = (process.env.NEXT_PUBLIC_SITE_URL || '').trim().replace(/\/$/, '');
  if (env && /^https?:\/\//i.test(env) && !env.includes('0.0.0.0') && !env.includes('127.0.0.1') && !env.includes('localhost')) return env;
  const proto = (req.headers.get('x-forwarded-proto') || 'https').split(',')[0].trim();
  const host = (req.headers.get('x-forwarded-host') || req.headers.get('host') || '').split(',')[0].trim();
  if (host && !host.startsWith('0.0.0.0') && !host.startsWith('127.0.0.1') && !host.startsWith('localhost')) return proto + '://' + host;
  return 'https://projectmisfitsrp.com';
}
