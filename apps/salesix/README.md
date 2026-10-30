# Salesix (sandbox)

Voice-agent platform from the `salesix-demo` repo, sandbox environment. Ten containers behind the host nginx:
postgres, redis, backend, python-service, frontendv2, landing, admin, demo, pitch, n8n.

Not deployed here: the compose nginx (the host nginx does that), the LiveKit agent (it runs on LiveKit Cloud),
`smartflo-bridge` and `newrelic-agent`.

| Host | Container | Loopback port |
|------|-----------|---------------|
| api.salesix.ai | backend | 3110 |
| app.salesix.ai | frontendv2 | 3111 |
| salesix.ai (+www redirect) | landing | 3112 |
| admin.salesix.ai | admin | 3113 |
| demo.salesix.ai | demo | 3114 |
| pitch.salesix.ai | pitch | 3115 |
| n8n.salesix.ai | n8n | 3116 |

Images are built on your workstation and pulled by the server; the server never builds.

## 1. Build and push the images (workstation)

```bash
cd apps/salesix
cp build.env.example build.env     # set SALESIX_SRC and NEXT_PUBLIC_DEMO_API_KEY
docker login ghcr.io -u <github-user>   # token with write:packages
./build-and-push.sh                 # or: ./build-and-push.sh backend landing
```

Builds target `linux/amd64`. `NEXT_PUBLIC_*` values are baked in at build time, so a URL change needs a rebuild.
`frontendv2` copies `frontendv2/.env.production` (including `NEXTAUTH_SECRET`) into its image: keep that GHCR package **private**.

## 2. Prepare the server

1. DNS A records for `salesix.ai`, `www`, `app`, `api`, `admin`, `demo`, `pitch`, `n8n` pointing at the server (DNS-only if on Cloudflare until certs are issued).
2. `docker login ghcr.io -u <github-user>` (token with `read:packages`).
3. Create the env files in `apps/salesix/` (copy your sandbox values; the `*.example` files list the variables):
   - `backend.env` (from `backend/.env.sandbox`): must also contain `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `REDIS_PASSWORD`,
     `DATABASE_URL=postgresql://<user>:<pw>@postgres:5432/<db>?schema=public`, `REDIS_URL=redis://:<redis pw>@redis:6379`,
     `PYTHON_SERVICE_URL=http://python-service:8001`, `PORT=3000`.
   - `python-service.env` (from `backend/livekit/.env`)
   - `frontendv2.env` (from `frontendv2/.env.production`)
4. Check `ss -ltnp` for the loopback ports; change them in `.env` if any clash.

`.env` (compose settings, Redis password) is created by the setup script, taking `REDIS_PASSWORD` from `backend.env`. The script refuses to start if it doesn't match the password inside `REDIS_URL`.

## 3. Deploy

```bash
sudo ./scripts/setup-salesix.sh your-email@example.com
```

Pulls the images, starts the stack, waits for `/health`, then creates the nginx host and certbot cert for each name.

## Operations

```bash
cd apps/salesix
docker compose ps
docker compose logs -f backend
docker compose pull && docker compose up -d      # after pushing new images
SALESIX_IMAGE_TAG=<old-tag> docker compose up -d # roll back (push versioned tags with build.env)
docker stats --no-stream                         # memory (containers are capped, see mem_limit)
```

Backend start runs `prisma migrate deploy`, so a failing migration shows in `docker compose logs backend`.

## Notes

- Set `TWILIO_WEBHOOK_URL` in `backend.env`; the sandbox file ships with a placeholder.
- The LiveKit Cloud agent is deployed separately (`lk agent deploy`); its `BACKEND_URL` must be `https://api.salesix.ai`.
- Database: `docker compose exec postgres pg_dump -U <user> <db> > salesix-$(date +%F).sql` (own Postgres, not shared with other apps).
