# Life Game Deployment

Docker Compose deployment for Life Game: the server and web app (Node, Postgres). The image is built and pushed from the `life-game` repo with `./deploy.sh` to `ghcr.io/msvhora/life-game` and pulled here.

The Mac agent and the Android app send their data to this server; the web app is served from the same address.

## Included Files

- [`docker-compose.yml`](docker-compose.yml): Runs the app (`ghcr.io/msvhora/life-game`) and its Postgres database.
- [`.env.example`](.env.example): Environment template (port, image tag, public URL, secrets, optional Solidtime).
- [`nginx-life-game.conf.example`](nginx-life-game.conf.example): Reverse proxy configuration for Nginx.
- [`backup.sh`](backup.sh) / [`restore.sh`](restore.sh): Database dump (optionally to Google Cloud Storage or, with rclone, Google Drive) and restore.
- `config/`: Optional personal settings (`*.local.yml`, for example `clients.local.yml` with client rates). Anything missing falls back to the defaults built into the image. Local files in here are git-ignored.

---

## Deployment Steps

### Quick: the setup script
From the repository root:
```bash
sudo ./scripts/setup-life-game.sh life.yourdomain.com your-email@example.com
```
It creates `.env` with generated secrets, asks you for the admin password (stored only as a hash), generates the phone push keys, pulls the image, starts it, and sets up Nginx and SSL.

### Manual steps

#### 1. Log in to GHCR (only if the package is private)
```bash
docker login ghcr.io -u msvhora   # token with read:packages
```

#### 2. Copy and fill the environment file
```bash
cd apps/life-game
cp .env.example .env
```
Set `PUBLIC_URL`, `POSTGRES_PASSWORD` (`openssl rand -hex 24`), `SESSION_SECRET` (`openssl rand -hex 32`), `ADMIN_PASSWORD_HASH` and the `VAPID_*` keys. The commands to produce the last two are in `.env.example`. If port `3017` is taken, change `FORWARD_APP_PORT`.

#### 3. Start
```bash
docker compose pull && docker compose up -d
docker compose ps
curl -s http://127.0.0.1:3017/health     # {"status":"ok","db":true}
```

### Updating to a new image
```bash
docker compose pull && docker compose up -d
```
To pin a version, set `LIFE_GAME_IMAGE_TAG` in `.env` (a release like `1.2.0` or a short git SHA). Database migrations run automatically on start.

---

## Moving your data from another machine (for example your Mac)
On the Mac, in the `life-game` repo, take a dump:
```bash
docker compose exec -T db pg_dump -U life -d life --no-owner | gzip -9 > life-game.sql.gz
scp life-game.sql.gz youruser@your-server:~/
```
On the server:
```bash
cd apps/life-game && ./restore.sh ~/life-game.sql.gz   # type: restore
rm ~/life-game.sql.gz
```
Device tokens are part of the data, so the Mac agent and the phone app keep working after you only change their server address.

## Backups
```bash
./backup.sh                       # writes backups/life-game-<time>.sql.gz, then uploads it if configured
```
Set `GCS_BACKUP_BUCKET` and `GCS_CREDENTIALS_BASE64` (a service-account key, base64) in `.env` and `backup.sh` also uploads to `gs://<bucket>/backups/`, checks the uploaded size, and deletes bucket copies older than 30 days (`RETENTION_DAYS`). `gcloud` runs in a container, so nothing is installed on the host. `scripts/setup-life-game.sh` installs a daily 03:15 cron entry (`/etc/cron.d/life-game-backup`, log `/var/log/life-game-backup.log`) when these are set.

For Google Drive instead, configure `rclone` (a remote called `gdrive`) and run with `BACKUP_TARGET=gdrive:life-game-backups ./backup.sh`.

Try `restore.sh` on a spare machine once before you rely on it.

## Freelance meter (optional)
Create an API token in Solidtime (profile), then set `TIMETRACKER_API_URL` (for example `https://time.yourdomain.com/api`) and `TIMETRACKER_API_TOKEN` in `.env`, and put your clients and rates in `config/clients.local.yml` (copy the example from the `life-game` repo). Restart with `docker compose up -d`.

---

## Reverse Proxy & SSL Setup

### Option A: Using the Repository Helper Script
From the repository root:
```bash
sudo ./scripts/setup-nginx-domain.sh life.yourdomain.com 3017 your-email@example.com
```

### Option B: Manual Nginx Configuration
1. Copy the Nginx site configuration:
   ```bash
   sudo cp nginx-life-game.conf.example /etc/nginx/sites-available/life-game.conf
   sudo ln -s /etc/nginx/sites-available/life-game.conf /etc/nginx/sites-enabled/
   ```
2. Replace `life.yourdomain.com` in the file with your actual domain.
3. Test and reload Nginx:
   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```
4. Generate the SSL certificate:
   ```bash
   sudo certbot --nginx -d life.yourdomain.com
   ```

---

## Troubleshooting

| Symptom | Check |
|---|---|
| `docker compose pull` says access denied | The GHCR package is private: `docker login ghcr.io -u msvhora` with a `read:packages` token, or make the package public |
| App does not start | `docker compose logs app` (a missing `.env` value is named there) |
| 502 from Nginx | `FORWARD_APP_PORT` in `.env` differs from the port in the Nginx file |
| Phone or Mac says the token is refused | The data was not restored, so the device does not exist yet: create it in the web app (More > Connect a device) |
