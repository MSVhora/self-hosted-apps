#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOLIDTIME_DIR="${REPO_ROOT}/apps/solidtime"

DOMAIN="${1:-}"
EMAIL="${2:-}"
PORT="8000"

echo "=========================================================="
echo " Setting up Solidtime Application"
echo "=========================================================="

cd "${SOLIDTIME_DIR}"

# 1. Initialize .env if missing
if [ ! -f ".env" ]; then
    echo "Creating .env from .env.example..."
    cp .env.example .env
    RANDOM_DB_PASS="$(openssl rand -hex 16)"
    sed -i "s/change_this_secure_database_password/${RANDOM_DB_PASS}/g" .env
    echo "Generated secure random DB_PASSWORD in .env"
fi

if [ -n "${DOMAIN}" ]; then
    sed -i "s|^APP_URL=.*|APP_URL=https://${DOMAIN}|g" .env || true
fi

# 2. Ensure data directories exist with proper write permissions for container user (1000:1000)
mkdir -p data/logs data/app-storage
chown -R 1000:1000 data/ || true
chmod -R 777 data/ || true

# 3. Generate Application & Passport Keys if not present
if grep -q "^APP_KEY=base64:" .env 2>/dev/null; then
    echo "Application keys already configured in .env. Skipping key generation."
else
    echo "Generating Application & OAuth Keys into .env..."
    sed -i '/^APP_KEY=/d; /^PASSPORT_PRIVATE_KEY=/d; /^PASSPORT_PUBLIC_KEY=/d' .env
    echo "" >> .env
    echo "# --- Auto-generated Encryption Keys ---" >> .env
    docker run --rm solidtime/solidtime:latest php artisan self-host:generate-keys >> .env
    echo "Keys successfully written to .env."
fi

# 4. Run database migrations
echo "Running database migrations..."
docker compose run --rm scheduler php artisan migrate --force

# 5. Start stack
echo "Starting Solidtime containers..."
docker compose up -d

echo "Solidtime is running locally on port ${PORT}."

# 6. Optional Nginx & SSL setup
if [ -z "${DOMAIN}" ] && [ -t 0 ]; then
    echo ""
    read -rp "Do you want to configure Nginx & SSL for Solidtime now? (y/N): " SETUP_NGINX
    if [[ "${SETUP_NGINX}" =~ ^[Yy]$ ]]; then
        read -rp "Enter domain for Solidtime (e.g. time.yourdomain.com): " DOMAIN
        read -rp "Enter email for Certbot SSL (optional, press Enter to skip): " EMAIL
    fi
fi

if [ -n "${DOMAIN}" ]; then
    echo "Configuring Nginx reverse proxy and SSL for ${DOMAIN}..."
    bash "${SCRIPT_DIR}/setup-nginx-domain.sh" "${DOMAIN}" "${PORT}" "${EMAIL}"
fi

echo "=========================================================="
echo " Solidtime setup finished successfully!"
echo "=========================================================="
