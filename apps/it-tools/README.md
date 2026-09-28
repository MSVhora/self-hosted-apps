# IT-Tools Deployment

This directory contains a complete Docker Compose deployment configuration for [IT-Tools](https://github.com/CorentinTh/it-tools) (collection of handy online tools for developers & IT people).

## Features
- Over 70+ client-side tools (Text Diff, JSON/YAML/XML formatters, Hash generators, JWT parsers, Base64 converters, Docker run to Compose converter, QR Code tools, and more).
- Purely client-side execution (no tracking, no data leaves the browser).
- Extremely lightweight container footprint (~30MB RAM).

## Included Files

- [`docker-compose.yml`](docker-compose.yml): Runs the IT-Tools web server container.
- [`.env.example`](.env.example): Environment variable template for port and image tag.
- [`nginx-it-tools.conf.example`](nginx-it-tools.conf.example): Reverse proxy configuration for Nginx.

---

## Deployment Steps

### 1. Copy Environment File
```bash
cd apps/it-tools
cp .env.example .env
```

### 2. Configure Port (Optional)
If port `8080` is already in use by another service on your host, edit `.env` and change `FORWARD_APP_PORT`:
```env
FORWARD_APP_PORT=8080
```

### 3. Start the Container
```bash
docker compose up -d
```

Verify that the container is healthy:
```bash
docker compose ps
```

---

## Reverse Proxy & SSL Setup

### Option A: Using the Repository Helper Script
From the repository root:
```bash
sudo ./scripts/setup-nginx-domain.sh tools.yourdomain.com 8080 your-email@example.com
```

### Option B: Manual Nginx Configuration
1. Copy the Nginx site configuration:
   ```bash
   sudo cp nginx-it-tools.conf.example /etc/nginx/sites-available/it-tools.conf
   sudo ln -s /etc/nginx/sites-available/it-tools.conf /etc/nginx/sites-enabled/
   ```
2. Replace `tools.yourdomain.com` in `/etc/nginx/sites-available/it-tools.conf` with your actual domain.
3. Test and reload Nginx:
   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```
4. Generate the SSL certificate using Certbot:
   ```bash
   sudo certbot --nginx -d tools.yourdomain.com
   ```
