// Optional: post store events to a staff Discord channel through a channel webhook.
// Set STORE_ORDERS_WEBHOOK_URL in Coolify (Channel settings -> Integrations -> Webhooks).
const money = (cents, cur = 'usd') =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: String(cur).toUpperCase() }).format((cents || 0) / 100);

export async function notifyStaff({ title, color = 0xa200ec, lines = [], fields = [] }) {
  const url = (process.env.STORE_ORDERS_WEBHOOK_URL || '').trim();
  if (!/^https:\/\/(?:ptb\.|canary\.)?discord(?:app)?\.com\/api\/webhooks\//.test(url)) return;
  try {
    await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'PMv2 Store',
        allowed_mentions: { parse: [] },
        embeds: [{
          title: String(title).slice(0, 250),
          description: lines.join('\n').slice(0, 4000),
          color,
          fields: fields.slice(0, 20).map(f => ({ name: String(f.name).slice(0, 250), value: String(f.value || '-').slice(0, 1000), inline: !!f.inline })),
          timestamp: new Date().toISOString(),
          footer: { text: 'projectmisfitsrp.com' }
        }]
      }),
      cache: 'no-store'
    });
  } catch (e) {
    console.error('PMv2 staff notify failed:', e.message);
  }
}

export { money };
