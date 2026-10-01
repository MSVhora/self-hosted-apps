# HOUM Website Deployment

Docker Compose deployment for the HOUM website (Next.js). The image is built and pushed from the `houm-web` repo with `./deploy.sh` and pulled here from GHCR.

## Included Files

- [`docker-compose.yml`](docker-compose.yml): Runs the HOUM web container from `ghcr.io/msvhora/houm-web`.
- [`.env.example`](.env.example): Environment template (port, image tag, site URL, SMTP settings for the forms).
- [`nginx-houm.conf.example`](nginx-houm.conf.example): Reverse proxy configuration for Nginx.

---

## Deployment Steps

### 1. Log in to GHCR (only if the package is private)
```bash
docker login ghcr.io -u msvhora   # token with read:packages
```

### 2. Copy and fill the environment file
```bash
cd apps/houm
cp .env.example .env
```
Set `REVALIDATE_SECRET`, `SMTP_USER`, `SMTP_PASS`, `MAIL_FROM` and `FORM_TO_EMAIL`. If port `3000` is taken, change `FORWARD_APP_PORT`.

### 3. Start the container
```bash
docker compose pull && docker compose up -d
docker compose ps
```

### Updating to a new image
```bash
HOUM_IMAGE_TAG=<sha> docker compose pull && HOUM_IMAGE_TAG=<sha> docker compose up -d
```
(or edit `HOUM_IMAGE_TAG` in `.env`).

---

## Reverse Proxy & SSL Setup

### Option A: Using the Repository Helper Script
From the repository root:
```bash
sudo ./scripts/setup-nginx-domain.sh houm.yourdomain.com 3000 your-email@example.com
```

### Option B: Manual Nginx Configuration
1. Copy the Nginx site configuration:
   ```bash
   sudo cp nginx-houm.conf.example /etc/nginx/sites-available/houm.conf
   sudo ln -s /etc/nginx/sites-available/houm.conf /etc/nginx/sites-enabled/
   ```
2. Replace `houm.yourdomain.com` in the file with your actual domain.
3. Test and reload Nginx:
   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```
4. Generate the SSL certificate:
   ```bash
   sudo certbot --nginx -d houm.yourdomain.com
   ```
