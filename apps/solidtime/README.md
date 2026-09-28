# Solidtime Deployment

This folder contains a complete Docker Compose deployment configuration for [Solidtime](https://solidtime.io) (open-source time tracking).

## Included Files

- [`docker-compose.yml`](docker-compose.yml): Runs Solidtime HTTP web server, Background Queue Worker, Scheduler, and PostgreSQL 16.
- [`.env.example`](.env.example): Single consolidated environment configuration template for Docker, PostgreSQL, SMTP, and application security keys.
- [`nginx-solidtime.conf.example`](nginx-solidtime.conf.example): Reverse proxy configuration for Nginx.

---

## Deployment Steps

### 1. Copy Environment File
```bash
cd apps/solidtime
cp .env.example .env
```

### 2. Configure Database & Domain
Open `.env` and set:
- `DB_PASSWORD`: A secure database password.
- `APP_URL`: Your actual public URL (e.g., `https://time.yourdomain.com`).
- `MAIL_*`: Your SMTP server settings (needed for invitations and password resets).

### 3. Generate Encryption Keys
Run the artisan helper to generate your unique application and Passport OAuth keys:
```bash
docker compose run --rm scheduler php artisan self-host:generate-keys
```
Copy the printed `APP_KEY`, `PASSPORT_PRIVATE_KEY`, and `PASSPORT_PUBLIC_KEY` outputs directly into your `.env` file.

### 4. Run Database Migrations
Initialize the database tables:
```bash
docker compose run --rm scheduler php artisan migrate --force
```

### 5. Start the Stack
```bash
docker compose up -d
```

### 6. Configure Nginx & SSL (Certbot)
1. Copy the Nginx site configuration:
   ```bash
   sudo cp nginx-solidtime.conf.example /etc/nginx/sites-available/solidtime.conf
   sudo ln -s /etc/nginx/sites-available/solidtime.conf /etc/nginx/sites-enabled/
   ```
2. Replace `time.picmix.in` in `/etc/nginx/sites-available/solidtime.conf` with your actual domain.
3. Test and reload Nginx:
   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```
4. Generate the SSL certificate using Certbot:
   ```bash
   sudo certbot --nginx -d time.picmix.in
   ```

---

## Creating the Initial Admin User

### Method A: Create User via CLI (Recommended)
Run the following artisan command:
```bash
docker compose exec scheduler php artisan admin:user:create "Your Name" "your-email@example.com" --verify-email
```
This will print a generated password for your initial login.

To grant full Super Admin access, add your email to `.env`:
```env
SUPER_ADMINS="your-email@example.com"
```
and restart containers: `docker compose down && docker compose up -d`.

### Method B: Enable Web Registration Form
In `.env`, set:
```env
APP_ENABLE_REGISTRATION=true
```
Then recreate containers:
```bash
docker compose down && docker compose up -d
```
You can now register directly at `https://time.picmix.in/register`.
