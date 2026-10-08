# Project Misfits v2 — Coolify Deployment

## Current production configuration

- Repository: `LDVDanari/project-misfits-v2`
- Branch: `main`
- Build method: **Dockerfile**
- Exposed port: **3000**
- Health check: `/api/health`
- Production domain: `https://projectmisfitsrp.com`
- WWW domain: `https://www.projectmisfitsrp.com`

## Environment variables

Use the values from `.env.example`.

Recommended production values:

```text
NEXT_PUBLIC_SITE_URL=https://projectmisfitsrp.com
NEXT_PUBLIC_DISCORD_URL=https://discord.gg/hHrSekGueH
NEXT_PUBLIC_FIVEM_ADDRESS=178.239.199.29
NEXT_PUBLIC_FIVEM_CONNECT=fivem://connect/178.239.199.29
FIVEM_HOST=178.239.199.29
FIVEM_PORT=30120
DISCORD_INVITE_CODE=hHrSekGueH
ADMIN_USERNAME=<set-in-coolify>
ADMIN_PASSWORD=<set-in-coolify>
```

`FIVEM_PORT` is set to the standard FiveM port by default. Change it in Coolify if the PMv2 server uses a different status endpoint port.

## Deployment flow

1. Merge an approved pull request into `main`.
2. GitHub runs the build check.
3. Coolify pulls `main` and builds the Docker image.
4. Traefik routes the production domains to port 3000.
5. Verify `/api/health`, the homepage, store, and `/status`.

## Commerce

Checkout uses Stripe, and paid orders are delivered automatically through the store database.
Checkout stays switched off until both Stripe and the database are configured.

### 1. Database
1. Run `db/pmv2_store.sql` on the MySQL/MariaDB database your FiveM server uses.
2. Recommended: create the website-only login from the bottom of that file.
3. In Coolify set either `DATABASE_URL=mysql://user:pass@host:3306/dbname`
   or `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` (`DB_SSL=true` if your host needs it).

### 2. Log in with Discord
1. Discord Developer Portal -> your application (the bot's app is fine) -> **OAuth2**.
2. Add the redirect `https://projectmisfitsrp.com/api/auth/discord/callback`.
3. In Coolify set `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`, `DISCORD_REDIRECT_URI` (the URL above)
   and `CUSTOMER_SESSION_SECRET` (a long random string, 32+ characters).

### 3. Stripe
1. Set `STRIPE_SECRET_KEY` and a tax code (Stripe Tax default or `STRIPE_TAX_CODE`).
2. That's it. **No Stripe webhook is needed:**
   - orders are recorded the moment the buyer lands on the confirmation page, and
   - a background check every 2 minutes (`STORE_SYNC_SECONDS`, minimum 60) picks up anyone who
     closed the tab, plus refunds (last 3 days) and chargebacks (last 120 days).
3. Optional: if you ever want instant refund/chargeback handling, add a webhook endpoint
   `https://projectmisfitsrp.com/api/stripe/webhook` with `checkout.session.completed`,
   `checkout.session.async_payment_succeeded`, `charge.refunded`, `charge.dispute.created`,
   `charge.dispute.closed`, and put its signing secret in `STRIPE_WEBHOOK_SECRET`.
   Both can run together safely.

### 4. Store logs in Discord
Create a webhook in your log channel (Channel settings -> Integrations -> Webhooks) and set
`STORE_ORDERS_WEBHOOK_URL`. Every website order (with the coin balance before and after),
refund and chargeback is posted there. Put the same URL in `Config.LogWebhook` in
`fivem/pmv2_store/config.lua` so in-city coin spending and staff changes land in the same channel.

### 5. The city
Install `fivem/pmv2_store` on the FiveM server (see its `INSTALL.md`).

### What happens on a purchase
- Coins are added to the buyer's account instantly; they get a message in the city next time they're on.
- Packages are saved as waiting on setup. Staff finish them and run `/storedone PM-XXXXXX`
  in the city, or mark the order fulfilled in the owner dashboard.
- A full refund takes the coins back and revokes packages automatically. Partial refunds are
  flagged for staff.
- A chargeback takes that order's coins back right away (so they can't be spent) and alerts staff.
  If you win it, the coins are given back; if you lose, packages and priority are revoked.
- If a payment was already refunded or disputed by the time its order is recorded, nothing is handed out.

## Store intro music
The intro plays "Misfits After Dark", an original beat generated in the browser (no files, nothing to license).
To use your own track instead, set `NEXT_PUBLIC_INTRO_AUDIO_URL` (and optionally
`NEXT_PUBLIC_INTRO_AUDIO_TITLE` / `NEXT_PUBLIC_INTRO_AUDIO_ARTIST`). Only use music you have the rights to.
