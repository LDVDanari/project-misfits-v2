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
2. Stripe Dashboard -> Developers -> Webhooks -> add endpoint
   `https://projectmisfitsrp.com/api/stripe/webhook` with these events:
   `checkout.session.completed`, `checkout.session.async_payment_succeeded`,
   `charge.refunded`, `charge.dispute.created`, `charge.dispute.closed`.
3. Copy its signing secret into `STRIPE_WEBHOOK_SECRET`.

### 4. Optional staff alerts
Create a webhook in a staff Discord channel (Channel settings -> Integrations -> Webhooks) and set
`STORE_ORDERS_WEBHOOK_URL`. New orders, refunds and chargebacks get posted there.

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
