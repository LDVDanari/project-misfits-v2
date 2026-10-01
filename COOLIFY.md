# Project Misfits v2 — Coolify Deployment

## Recommended deployment: Dockerfile

1. Push this folder to a GitHub/GitLab repository.
2. In Coolify create a new **Application** from that repository.
3. Build Pack: **Dockerfile**.
4. Port: **3000**.
5. Add environment variables from `.env.example`.
6. Add your domain in Coolify after DNS is pointed to the server.
7. Health check path: `/api/health`.
8. Deploy.

## DNS

For a root domain, create an `A` record pointing to the public IP of the Coolify server. For `www`, either add another `A` record or a `CNAME` to the root domain, depending on your DNS provider.

## Before launch

Replace placeholder Discord/CFX links with the real values. Checkout is intentionally not connected yet; do not publish purchase buttons until a compliant commerce provider and exact product fulfillment flow are configured.
