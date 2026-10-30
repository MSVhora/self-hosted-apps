#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIFE_GAME_DIR="${REPO_ROOT}/apps/life-game"

DOMAIN="${1:-}"
EMAIL="${2:-}"

echo "=========================================================="
echo " Setting up Life Game"
echo "=========================================================="

cd "${LIFE_GAME_DIR}"
mkdir -p config

set_env() {
    local key="$1" value="$2"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        echo "${key}=${value}" >> .env
    fi
}

get_env() {
    grep -E "^$1=" .env | head -1 | cut -d= -f2- || true
}

# 1. Initialize .env if missing, and generate the secrets that must never be defaults
if [ ! -f ".env" ]; then
    echo "Creating .env from .env.example..."
    cp .env.example .env
fi
chmod 600 .env

if [ -z "$(get_env POSTGRES_PASSWORD)" ] || [ "$(get_env POSTGRES_PASSWORD)" = "change-me" ]; then
    set_env POSTGRES_PASSWORD "$(openssl rand -hex 24)"
    echo "Generated POSTGRES_PASSWORD in .env"
fi
if [ -z "$(get_env SESSION_SECRET)" ] || [ "$(get_env SESSION_SECRET)" = "change-me" ]; then
    set_env SESSION_SECRET "$(openssl rand -hex 32)"
    echo "Generated SESSION_SECRET in .env"
fi
if [ -n "${DOMAIN}" ]; then
    set_env PUBLIC_URL "https://${DOMAIN}"
    set_env VAPID_SUBJECT "https://${DOMAIN}"
fi

TAG="$(get_env LIFE_GAME_IMAGE_TAG)"
IMAGE="ghcr.io/msvhora/life-game:${TAG:-latest}"
PORT="$(get_env FORWARD_APP_PORT)"
PORT="${PORT:-3017}"

# 2. Pull the image
echo "Pulling ${IMAGE}..."
if ! docker compose pull; then
    echo "Error: could not pull the image." >&2
    echo "If the GHCR package is private, log in first:  docker login ghcr.io -u msvhora   (token with read:packages)" >&2
    exit 1
fi

# 3. Admin password (stored only as a hash)
if [ -z "$(get_env ADMIN_PASSWORD_HASH)" ]; then
    if [ -t 0 ]; then
        while true; do
            read -rsp "Choose an admin password for Life Game (12+ characters): " ADMIN_PW; echo
            read -rsp "Repeat it: " ADMIN_PW2; echo
            if [ "${ADMIN_PW}" = "${ADMIN_PW2}" ] && [ "${#ADMIN_PW}" -ge 12 ]; then break; fi
            echo "Passwords differ or are shorter than 12 characters. Try again."
        done
        HASH_LINE="$(printf '%s\n' "${ADMIN_PW}" | docker run --rm -i "${IMAGE}" node dist/cli/hash-password.js --stdin | tr -d '\r')"
        unset ADMIN_PW ADMIN_PW2
        set_env ADMIN_PASSWORD_HASH "${HASH_LINE#ADMIN_PASSWORD_HASH=}"
        echo "Saved the admin password hash in .env"
    else
        echo "Error: ADMIN_PASSWORD_HASH is empty and there is no terminal to ask for a password." >&2
        echo "Run:  printf '%s\\n' 'your password' | docker run --rm -i ${IMAGE} node dist/cli/hash-password.js --stdin   and put the line in ${LIFE_GAME_DIR}/.env" >&2
        exit 1
    fi
fi

# 4. Push-notification keys (reminders on the phone)
if [ -z "$(get_env VAPID_PUBLIC_KEY)" ]; then
    echo "Generating push notification keys..."
    docker run --rm "${IMAGE}" node dist/cli/vapid.js | tr -d '\r' | while IFS='=' read -r key value; do
        case "${key}" in
            VAPID_PUBLIC_KEY|VAPID_PRIVATE_KEY) set_env "${key}" "${value}" ;;
        esac
    done
fi

# 5. Start
echo "Starting Life Game via Docker Compose..."
docker compose up -d

echo "Waiting for the app to answer..."
for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
        echo "Life Game is running locally on port ${PORT}."
        break
    fi
    sleep 2
done

# 6. Optional Nginx & SSL setup
if [ -z "${DOMAIN}" ] && [ -t 0 ]; then
    echo ""
    read -rp "Do you want to configure Nginx & SSL for Life Game now? (y/N): " SETUP_NGINX
    if [[ "${SETUP_NGINX}" =~ ^[Yy]$ ]]; then
        read -rp "Enter domain for Life Game (e.g. life.yourdomain.com): " DOMAIN
        read -rp "Enter email for Certbot SSL (optional, press Enter to skip): " EMAIL
        set_env PUBLIC_URL "https://${DOMAIN}"
        set_env VAPID_SUBJECT "https://${DOMAIN}"
        docker compose up -d
    fi
fi

if [ -n "${DOMAIN}" ]; then
    echo "Configuring Nginx reverse proxy and SSL for ${DOMAIN}..."
    bash "${SCRIPT_DIR}/setup-nginx-domain.sh" "${DOMAIN}" "${PORT}" "${EMAIL}"
fi

# 7. Nightly database backup to GCS (only when the bucket and key are configured in .env)
if [ "$(id -u)" -eq 0 ] && [ -n "$(get_env GCS_BACKUP_BUCKET)" ] && [ -n "$(get_env GCS_CREDENTIALS_BASE64)" ]; then
    chmod +x "${LIFE_GAME_DIR}/backup.sh"
    cat > /etc/cron.d/life-game-backup <<CRON
# Life Game: nightly Postgres backup to GCS at 03:15 server time
PATH=/usr/local/bin:/usr/bin:/bin
15 3 * * * root ${LIFE_GAME_DIR}/backup.sh >> /var/log/life-game-backup.log 2>&1
CRON
    chmod 644 /etc/cron.d/life-game-backup
    echo "Installed /etc/cron.d/life-game-backup (daily 03:15, log: /var/log/life-game-backup.log)"
fi

echo "=========================================================="
echo " Life Game setup finished successfully!"
echo "=========================================================="
