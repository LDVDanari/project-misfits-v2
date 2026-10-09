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

## Commerce (Tebex)

Payments run through **Tebex**, the official FiveM store partner (Cfx.re requires it).
The website shows the store and builds the cart; Tebex signs the buyer in with their FiveM
account, takes the payment, and runs the delivery command on the FiveM server.

### 1. Tebex packages
1. In the Tebex control panel, create one package per coin bundle. **Name each package exactly like
   the site product** (e.g. `10 Misfit Coins`, `25 Misfit Coins`, ...). Matching names go live on the
   site automatically, with Tebex's price. Anything without a Tebex package shows COMING SOON.
   (If you'd rather use different names, set `TEBEX_PACKAGE_MAP` - see `.env.example`.)
2. On each coin package, add a **command** (run "even if the player is offline"):
   ```
   pmv2_tebex {id} {transaction} {packageId} {purchaseQuantity} 10
   ```
   The last number is the coins in ONE of that package (10, 25, 50, 100, 250, 500).
3. Add the same command as `pmv2_tebex_reverse ...` under **Chargeback** and **Refund** commands,
   so coins are taken back automatically.
4. Link the FiveM server: put `sv_tebexSecret <your secret>` at the bottom of `server.cfg`.

### 2. Website
In Coolify set `TEBEX_PUBLIC_TOKEN` (Tebex -> Integrations -> Headless API) and redeploy.
`/api/health` shows `checkoutReady: true` once packages are matched.

### 3. The city
Install / update `fivem/pmv2_store` (see its `INSTALL.md`) and set `Config.LogWebhook`
so purchases, coin spending and staff changes are logged to Discord.

### What happens on a purchase
1. The buyer adds coins on the site and presses **Continue to checkout**.
2. Tebex asks them to sign in with their FiveM (Cfx.re) account, then they pay on Tebex.
3. Tebex runs `pmv2_tebex` on the server. The coins are credited to the wallet of the Discord
   account that FiveM account plays with - right away if they're online, otherwise the next time
   they load in. Each Tebex transaction can only be credited once.
4. Refunds and chargebacks run `pmv2_tebex_reverse`, which takes those coins back.

Payments, refunds, coupons, sales and payouts are all managed in the Tebex control panel.

### Optional: coin balance on the checkout page
Set the store database (`DB_*` or `DATABASE_URL`) and Discord login (`DISCORD_CLIENT_ID`,
`DISCORD_CLIENT_SECRET`, `DISCORD_REDIRECT_URI`, `CUSTOMER_SESSION_SECRET`) and players can log in
with Discord on the checkout page to see their balance. Checkout works without it.

## Store intro music
The intro plays "Misfits After Dark", an original beat generated in the browser (no files, nothing to license).
To use your own track instead, set `NEXT_PUBLIC_INTRO_AUDIO_URL` (and optionally
`NEXT_PUBLIC_INTRO_AUDIO_TITLE` / `NEXT_PUBLIC_INTRO_AUDIO_ARTIST`). Only use music you have the rights to.
