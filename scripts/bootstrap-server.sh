#!/usr/bin/env bash

set -euo pipefail

# Ensure script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

DOMAIN="time.picmix.in"
EMAIL="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOLIDTIME_DIR="${REPO_ROOT}/apps/solidtime"

echo "=========================================================="
echo " Starting Full Server Provisioning & Solidtime Setup"
echo " Target Domain: ${DOMAIN}"
echo "=========================================================="

# 1. Setup 8GB Swap
echo ""
echo ">>> [Step 1/5] Setting up 8GB Swap Memory..."
bash "${SCRIPT_DIR}/setup-swap.sh"

# 2. Install Core Stack (Nginx, Docker CE, Docker Compose, Certbot)
echo ""
echo ">>> [Step 2/5] Installing Core Packages (Docker, Nginx, Certbot)..."
bash "${SCRIPT_DIR}/install-core-stack.sh"

# Ensure docker service is running
systemctl start docker

# 3. Configure Solidtime Application
echo ""
echo ">>> [Step 3/5] Configuring Solidtime Environment..."
cd "${SOLIDTIME_DIR}"

if [ ! -f ".env" ]; then
    cp .env.example .env
    # Generate random secure DB password
    RANDOM_DB_PASS="$(openssl rand -hex 16)"
    sed -i "s/change_this_secure_database_password/${RANDOM_DB_PASS}/g" .env
    echo "Generated secure DB_PASSWORD in .env"
fi

# Ensure data directories exist with proper write permissions for container user (1000:1000)
mkdir -p data/logs data/app-storage
chown -R 1000:1000 data/ || true
chmod -R 777 data/ || true

# 4. Generate Application & Passport Keys (Only if not already generated)
echo ""
echo ">>> [Step 4/5] Checking Application & OAuth Keys..."
if grep -q "^APP_KEY=base64:" .env 2>/dev/null; then
    echo "Application keys already configured in .env. Skipping key generation."
else
    echo "Generating Application & OAuth Keys..."
    docker compose run --rm scheduler php artisan self-host:generate-keys || true
fi

# Run database migrations
echo "Running Database Migrations..."
docker compose run --rm scheduler php artisan migrate --force

# Launch application stack
echo "Starting Docker Compose services..."
docker compose up -d

# 5. Configure Nginx and SSL
echo ""
echo ">>> [Step 5/5] Configuring Nginx Reverse Proxy & SSL for ${DOMAIN}..."
if [ -n "${EMAIL}" ]; then
    bash "${SCRIPT_DIR}/setup-nginx-domain.sh" "${DOMAIN}" 8000 "${EMAIL}"
else
    bash "${SCRIPT_DIR}/setup-nginx-domain.sh" "${DOMAIN}" 8000
fi

echo "=========================================================="
echo " Server Provisioning Complete!"
echo " Solidtime is live at: https://${DOMAIN}"
echo "=========================================================="
