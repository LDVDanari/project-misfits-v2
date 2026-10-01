# Project Misfits v2 Website

Production-ready Next.js storefront/community site starter for Project Misfits v2.

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

Use the included `Dockerfile`; expose port 3000 and use `/api/health` as the health-check path. See `COOLIFY.md`.

## Environment

Copy `.env.example` to `.env.local` and set the real values.

Checkout remains intentionally disabled until the commerce provider is selected and connected.
