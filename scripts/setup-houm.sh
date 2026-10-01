#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOUM_DIR="${REPO_ROOT}/apps/houm"

DOMAIN="${1:-}"
EMAIL="${2:-}"
PORT="3000"

echo "=========================================================="
echo " Setting up HOUM Website Application"
echo "=========================================================="

cd "${HOUM_DIR}"

# 1. Initialize .env if missing
if [ ! -f ".env" ]; then
    echo "Creating .env from .env.example..."
    cp .env.example .env
    RANDOM_SECRET="$(openssl rand -hex 24)"
    sed -i "s|^REVALIDATE_SECRET=.*|REVALIDATE_SECRET=${RANDOM_SECRET}|" .env
    echo "Generated random REVALIDATE_SECRET in .env"
    echo "NOTE: set SMTP_USER, SMTP_PASS, MAIL_FROM and FORM_TO_EMAIL in ${HOUM_DIR}/.env for the website forms."
fi

if [ -n "${DOMAIN}" ]; then
    sed -i "s|^SITE_URL=.*|SITE_URL=https://${DOMAIN}|g" .env || true
fi

# 2. Start HOUM container
echo "Pulling and starting HOUM via Docker Compose..."
docker compose pull
docker compose up -d

echo "HOUM is running locally on port ${PORT}."

# 3. Optional Nginx & SSL setup
if [ -z "${DOMAIN}" ] && [ -t 0 ]; then
    echo ""
    read -rp "Do you want to configure Nginx & SSL for HOUM now? (y/N): " SETUP_NGINX
    if [[ "${SETUP_NGINX}" =~ ^[Yy]$ ]]; then
        read -rp "Enter domain for HOUM (e.g. houm.yourdomain.com): " DOMAIN
        read -rp "Enter email for Certbot SSL (optional, press Enter to skip): " EMAIL
    fi
fi

if [ -n "${DOMAIN}" ]; then
    echo "Configuring Nginx reverse proxy and SSL for ${DOMAIN}..."
    bash "${SCRIPT_DIR}/setup-nginx-domain.sh" "${DOMAIN}" "${PORT}" "${EMAIL}"
fi

echo "=========================================================="
echo " HOUM setup finished successfully!"
echo "=========================================================="
