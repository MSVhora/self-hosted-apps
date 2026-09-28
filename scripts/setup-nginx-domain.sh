#!/usr/bin/env bash

set -euo pipefail

# Default configuration
DOMAIN="${1:-time.picmix.in}"
UPSTREAM_PORT="${2:-8000}"
UPSTREAM_HOST="127.0.0.1"
EMAIL="${3:-}"

# Check for root/sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root or with sudo." >&2
    exit 1
fi

echo "=========================================================="
echo " Setting up Nginx Reverse Proxy & SSL for: ${DOMAIN}"
echo " Upstream Target: http://${UPSTREAM_HOST}:${UPSTREAM_PORT}"
echo "=========================================================="

# 1. Verify dependencies
for cmd in nginx certbot; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "Error: ${cmd} is not installed. Please run ./scripts/install-core-stack.sh first." >&2
        exit 1
    fi
done

# 2. Write Nginx configuration
CONFIG_AVAILABLE="/etc/nginx/sites-available/${DOMAIN}.conf"
CONFIG_ENABLED="/etc/nginx/sites-enabled/${DOMAIN}.conf"

echo "[1/4] Generating Nginx server block at ${CONFIG_AVAILABLE}..."

cat > "${CONFIG_AVAILABLE}" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    client_max_body_size 50M;

    location / {
        proxy_pass http://${UPSTREAM_HOST}:${UPSTREAM_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 90;
        proxy_connect_timeout 90;
    }
}
EOF

# 3. Enable site configuration
echo "[2/4] Enabling site in Nginx..."
ln -sf "${CONFIG_AVAILABLE}" "${CONFIG_ENABLED}"

# Test Nginx syntax
echo "[3/4] Testing and reloading Nginx configuration..."
nginx -t
systemctl reload nginx

# 4. Request SSL Certificate via Certbot
echo "[4/4] Requesting Let's Encrypt SSL certificate via Certbot..."

CERTBOT_ARGS=(--nginx -d "${DOMAIN}" --non-interactive --agree-tos --redirect)

if [ -n "${EMAIL}" ]; then
    CERTBOT_ARGS+=(-m "${EMAIL}")
else
    CERTBOT_ARGS+=(--register-unsafely-without-email)
fi

certbot "${CERTBOT_ARGS[@]}"

echo "=========================================================="
echo " SSL & Reverse Proxy Setup Successful!"
echo " Domain: https://${DOMAIN}"
echo "=========================================================="
