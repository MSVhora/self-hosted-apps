#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IT_TOOLS_DIR="${REPO_ROOT}/apps/it-tools"

DOMAIN="${1:-}"
EMAIL="${2:-}"
PORT="8080"

echo "=========================================================="
echo " Setting up IT-Tools Application"
echo "=========================================================="

cd "${IT_TOOLS_DIR}"

# 1. Initialize .env if missing
if [ ! -f ".env" ]; then
    echo "Creating .env from .env.example..."
    cp .env.example .env
fi

# 2. Start IT-Tools container
echo "Starting IT-Tools via Docker Compose..."
docker compose up -d

echo "IT-Tools is running locally on port ${PORT}."

# 3. Optional Nginx & SSL setup
if [ -z "${DOMAIN}" ] && [ -t 0 ]; then
    echo ""
    read -rp "Do you want to configure Nginx & SSL for IT-Tools now? (y/N): " SETUP_NGINX
    if [[ "${SETUP_NGINX}" =~ ^[Yy]$ ]]; then
        read -rp "Enter domain for IT-Tools (e.g. tools.yourdomain.com): " DOMAIN
        read -rp "Enter email for Certbot SSL (optional, press Enter to skip): " EMAIL
    fi
fi

if [ -n "${DOMAIN}" ]; then
    echo "Configuring Nginx reverse proxy and SSL for ${DOMAIN}..."
    bash "${SCRIPT_DIR}/setup-nginx-domain.sh" "${DOMAIN}" "${PORT}" "${EMAIL}"
fi

echo "=========================================================="
echo " IT-Tools setup finished successfully!"
echo "=========================================================="
