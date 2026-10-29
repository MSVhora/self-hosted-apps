#!/usr/bin/env bash
# Dumps the Life Game database to apps/life-game/backups/ (gzip) and, if BACKUP_TARGET is set in the
# environment (an rclone remote such as gdrive:life-game-backups), uploads it. Keeps 30 days.
# Cron example:  15 3 * * *  /path/to/self-hosted-apps/apps/life-game/backup.sh >> /var/log/life-game-backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")"
set -a; . ./.env; set +a

mkdir -p backups
file="backups/life-game-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
docker compose exec -T db pg_dump -U "${POSTGRES_USER:-life}" -d "${POSTGRES_DB:-life}" --no-owner | gzip -9 > "$file"
[ "$(wc -c < "$file")" -gt 500 ] || { echo "dump looks empty, removing" >&2; rm -f "$file"; exit 1; }
chmod 600 "$file"
echo "backup written: $file"

if [ -n "${BACKUP_TARGET:-}" ]; then
    rclone copy "$file" "$BACKUP_TARGET"
    rclone delete "$BACKUP_TARGET" --min-age 30d --include 'life-game-*.sql.gz'
    echo "uploaded to $BACKUP_TARGET"
fi
find backups -name 'life-game-*.sql.gz' -mtime +30 -delete
