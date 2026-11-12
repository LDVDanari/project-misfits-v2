# Project Misfits v2 Website

Production Next.js website/storefront for **Project Misfits v2**.

## Stack

- Next.js 15 App Router
- React 19
- Docker / Coolify
- GitHub Actions build validation
- Server-side FiveM status endpoint
- Client-side cart stored locally in the browser

## Local development

```bash
npm install
npm run dev
```

Open http://localhost:3000.

## Production

```bash
npm run build
npm start
```

## Coolify

Use the included `Dockerfile`, expose port **3000**, and use `/api/health` as the health-check path.

Production domain:

```text
https://projectmisfitsrp.com
```

## Environment

Copy `.env.example` to `.env.local` for local development.

The current production defaults are already safe public values, but Coolify environment variables can override the FiveM host/port when needed.

## Commerce

The storefront and browser cart are active in the UI. Payment processing remains intentionally disabled until PMv2 selects and configures its production commerce provider.

Do not add card handling, payment secrets, or homemade payment processing directly to this application.

## Deployment workflow

1. Build features on a branch.
2. Open a pull request into `main`.
3. Let **PMv2 Build Check** run.
4. Merge after the build succeeds.
5. Coolify deploys `main`.

## Admin foundation

A protected read-only admin dashboard exists at `/admin`.

Set both of these in Coolify before attempting to use it:

```text
ADMIN_USERNAME=...
ADMIN_PASSWORD=...
```

If either value is missing, the admin route returns 404. The current dashboard is intentionally read-only; write controls should not be enabled until database persistence, role-based authentication and audit logging are added.

## Currencies (USD + CAD)

Prices come from Tebex. To take Canadian dollars:

1. Tebex control panel -> Settings -> Checkout -> **Supported currencies**: turn on **CAD**.
2. Optional: Tebex -> Webstore -> **Regional pricing**: set Canada's prices yourself (otherwise Tebex converts the USD price).
3. Make sure `TEBEX_PRIVATE_KEY` is set in Coolify. With it the site asks Tebex for each visitor's own prices,
   so players in Canada see `$17.13 CAD` instead of the USD price. Without it everyone sees the base (USD) price,
   but Tebex still charges Canadians in CAD at checkout.

## Package names in Tebex

A site product goes live when a Tebex package with the same name exists (or map it with `TEBEX_PACKAGE_MAP`).
New ones: **Unban Package** (`unban`) and **VIP Gun Card Package** (`vip-gun-card`).

## Discord receipts

Buyers who log in with Discord on the checkout page get a private receipt card in their Discord DMs from the PMv2 bot.

1. In Discord, run `/store webhook` (management only). The bot makes a hidden `🧾・store-receipts` channel and shows a webhook URL.
2. Coolify -> environment: `DISCORD_RECEIPT_WEBHOOK_URL` = that URL.
3. Tebex -> Developers -> Webhooks -> Endpoints -> add `https://projectmisfitsrp.com/api/tebex/webhook`, tick **payment.completed**,
   **payment.refunded** and the four **payment.dispute** events (refund / chargeback alerts for the Dono Team).
   Copy the endpoint's secret into `TEBEX_WEBHOOK_SECRET`, redeploy, then press **Validate** in Tebex.
4. `/api/health` shows `discordReceipts: true` when both values are set.

The site only sends the transaction ID, package names, prices, the FiveM name and the Discord ID to Discord: never emails, IPs or card details.
Buyers who didn't log in with Discord still show up in the staff channel, where staff can send the receipt by hand.
