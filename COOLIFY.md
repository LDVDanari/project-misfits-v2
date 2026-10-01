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

Checkout remains disabled until a production commerce provider is selected and configured. The site cart is currently client-side only and does not process payments.
