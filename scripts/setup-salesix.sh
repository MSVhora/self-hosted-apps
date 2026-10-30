#!/usr/bin/env bash
# Deploy Salesix (sandbox): prebuilt GHCR images behind the host nginx.
# Usage: sudo ./scripts/setup-salesix.sh [email]
# Domains are fixed to *.salesix.ai (the images bake those URLs in at build time).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SALESIX_DIR="${REPO_ROOT}/apps/salesix"
EMAIL="${1:-}"
ROOT_DOMAIN="salesix.ai"

echo "=========================================================="
echo " Setting up Salesix (sandbox)"
echo "=========================================================="

cd "${SALESIX_DIR}"

get_env() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- || true; }
set_env() {
    if grep -q "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else echo "$1=$2" >> .env; fi
}

# 1. Env files: .env is generated, the app env files hold real secrets and must be provided
if [ ! -f .env ]; then
    cp .env.example .env
    chmod 600 .env
    # Reuse the password already in backend.env so the two files agree; otherwise generate one
    EXISTING_PW="$(grep -E '^REDIS_PASSWORD=' backend.env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true)"
    set_env REDIS_PASSWORD "${EXISTING_PW:-$(openssl rand -hex 24)}"
    echo "Created .env (REDIS_PASSWORD $([ -n "${EXISTING_PW}" ] && echo 'taken from backend.env' || echo 'generated'))."
fi

missing=0
for f in backend.env python-service.env frontendv2.env; do
    if [ ! -f "${f}" ]; then
        echo "Missing ${SALESIX_DIR}/${f}: copy ${f%.env}.env.example (or your sandbox env file) and fill it in." >&2
        missing=1
    else
        chmod 600 "${f}"
    fi
done
[ "${missing}" -eq 0 ] || exit 1

REDIS_PW="$(get_env REDIS_PASSWORD)"
if ! grep -q "^REDIS_PASSWORD=${REDIS_PW}\$" backend.env || ! grep -q "redis://:${REDIS_PW}@redis" backend.env; then
    echo "Error: REDIS_PASSWORD in .env must match REDIS_PASSWORD and REDIS_URL (redis://:<pw>@redis:6379) in backend.env." >&2
    exit 1
fi

# 2. Pull images
echo "Pulling images..."
if ! docker compose pull; then
    echo "Error: could not pull images. If the GHCR packages are private run: docker login ghcr.io (token with read:packages)" >&2
    exit 1
fi

# 3. Start
docker compose up -d

port() { local v; v="$(get_env "$1")"; echo "${v:-$2}"; }
BACKEND_PORT="$(port BACKEND_PORT 3110)"
echo "Waiting for the backend to answer..."
for _ in $(seq 1 45); do
    if curl -fsS "http://127.0.0.1:${BACKEND_PORT}/health" >/dev/null 2>&1; then
        echo "Backend is up on port ${BACKEND_PORT}."
        break
    fi
    sleep 4
done

# 4. Nginx + SSL (DNS for every name below must already point at this server)
declare -A SITES=(
    ["api.${ROOT_DOMAIN}"]="${BACKEND_PORT}"
    ["app.${ROOT_DOMAIN}"]="$(port FRONTEND_PORT 3111)"
    ["${ROOT_DOMAIN}"]="$(port LANDING_PORT 3112)"
    ["admin.${ROOT_DOMAIN}"]="$(port ADMIN_PORT 3113)"
    ["demo.${ROOT_DOMAIN}"]="$(port DEMO_PORT 3114)"
    ["pitch.${ROOT_DOMAIN}"]="$(port PITCH_PORT 3115)"
    ["n8n.${ROOT_DOMAIN}"]="$(port N8N_PORT 3116)"
)

if [ "$(id -u)" -ne 0 ]; then
    echo "Not root: skipping nginx/SSL. Re-run with sudo to configure the hosts." >&2
else
    for domain in "${!SITES[@]}"; do
        echo "Configuring nginx + SSL for ${domain} -> 127.0.0.1:${SITES[$domain]}"
        bash "${SCRIPT_DIR}/setup-nginx-domain.sh" "${domain}" "${SITES[$domain]}" "${EMAIL}"
    done

    # n8n executions can run for minutes
    sed -i 's/proxy_read_timeout 90;/proxy_read_timeout 600;/' "/etc/nginx/sites-available/n8n.${ROOT_DOMAIN}.conf"

    # www -> apex redirect
    WWW_CONF="/etc/nginx/sites-available/www.${ROOT_DOMAIN}.conf"
    cat > "${WWW_CONF}" <<NGINX
server {
    listen 80;
    server_name www.${ROOT_DOMAIN};
    location / {
        return 301 https://${ROOT_DOMAIN}\$request_uri;
    }
}
NGINX
    ln -sf "${WWW_CONF}" "/etc/nginx/sites-enabled/www.${ROOT_DOMAIN}.conf"
    CERTBOT_ARGS=(--nginx -d "www.${ROOT_DOMAIN}" --non-interactive --agree-tos --redirect)
    if [ -n "${EMAIL}" ]; then CERTBOT_ARGS+=(-m "${EMAIL}"); else CERTBOT_ARGS+=(--register-unsafely-without-email); fi
    certbot "${CERTBOT_ARGS[@]}"
    nginx -t && systemctl reload nginx

    # Daily database backup to Google Cloud Storage (see apps/salesix/backup.sh)
    chmod +x "${SALESIX_DIR}/backup.sh"
    cat > /etc/cron.d/salesix-backup <<CRON
# Salesix: daily Postgres backup to GCS at 02:00 server time
PATH=/usr/local/bin:/usr/bin:/bin
0 2 * * * root ${SALESIX_DIR}/backup.sh >> /var/log/salesix-backup.log 2>&1
CRON
    chmod 644 /etc/cron.d/salesix-backup
    echo "Installed /etc/cron.d/salesix-backup (daily 02:00, log: /var/log/salesix-backup.log)"
fi

echo "=========================================================="
echo " Salesix setup finished. Check:  cd ${SALESIX_DIR} && docker compose ps"
echo "=========================================================="
