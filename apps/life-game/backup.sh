#!/usr/bin/env bash
# Dumps the Life Game database to apps/life-game/backups/ (gzip), then uploads it:
#   - to Google Cloud Storage when GCS_BACKUP_BUCKET and GCS_CREDENTIALS_BASE64 are set in .env
#     (gcloud runs in a container, nothing is installed on the host), and/or
#   - with rclone when BACKUP_TARGET is set (e.g. gdrive:life-game-backups).
# Keeps RETENTION_DAYS (default 30) of backups in the bucket / rclone target and locally.
# Cron: installed at 03:15 daily by scripts/setup-life-game.sh when GCS is configured:
#   15 3 * * * root /path/to/self-hosted-apps/apps/life-game/backup.sh >> /var/log/life-game-backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"
set -a; . ./.env; set +a

RETENTION_DAYS="${RETENTION_DAYS:-30}"
GCLOUD_IMAGE="${GCLOUD_IMAGE:-gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine}"
GCS_PATH="${GCS_BACKUP_PATH:-backups}"

log() { echo "[$(date +'%F %T')] $*"; }

mkdir -p backups
name="life-game-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
file="backups/${name}"
docker compose exec -T db pg_dump -U "${POSTGRES_USER:-life}" -d "${POSTGRES_DB:-life}" --no-owner | gzip -9 > "${file}.partial" \
    || { rm -f "${file}.partial"; echo "pg_dump failed" >&2; exit 1; }
gzip -t "${file}.partial" || { rm -f "${file}.partial"; echo "dump is not valid gzip" >&2; exit 1; }
[ "$(wc -c < "${file}.partial")" -gt 500 ] || { echo "dump looks empty, removing" >&2; rm -f "${file}.partial"; exit 1; }
mv "${file}.partial" "${file}"
chmod 600 "${file}"
size="$(wc -c < "${file}" | tr -d ' ')"
log "backup written: ${file} (${size} bytes)"

# Google Cloud Storage
if [ -n "${GCS_BACKUP_BUCKET:-}" ]; then
    [ -n "${GCS_CREDENTIALS_BASE64:-}" ] || { echo "GCS_BACKUP_BUCKET is set but GCS_CREDENTIALS_BASE64 is empty" >&2; exit 1; }
    key="$(mktemp)"; chmod 600 "${key}"
    trap 'rm -f "${key}"' EXIT
    echo "${GCS_CREDENTIALS_BASE64}" | base64 -d > "${key}" || { echo "GCS_CREDENTIALS_BASE64 is not valid base64" >&2; exit 1; }

    gcloud_run() {
        docker run --rm -v "${key}:/key.json:ro" -v "$(pwd)/backups:/backups:ro" "${GCLOUD_IMAGE}" \
            sh -c 'gcloud auth activate-service-account --key-file=/key.json -q >/dev/null 2>&1 && '"$1"
    }

    dest="gs://${GCS_BACKUP_BUCKET}/${GCS_PATH}/${name}"
    log "uploading to ${dest}"
    gcloud_run "gcloud storage cp /backups/${name} ${dest} -q" || { echo "upload failed" >&2; exit 1; }
    remote_size="$(gcloud_run "gcloud storage ls -l ${dest}" | awk 'NR==1{print $1}')"
    [ "${remote_size}" = "${size}" ] || { echo "uploaded size ${remote_size:-?} != local ${size}" >&2; exit 1; }
    log "upload verified (${remote_size} bytes)"

    if [ "${RETENTION_DAYS}" -gt 0 ]; then
        cutoff="$(date -u -d "${RETENTION_DAYS} days ago" +%Y%m%d)"
        gcloud_run "gcloud storage ls gs://${GCS_BACKUP_BUCKET}/${GCS_PATH}/" | while read -r obj; do
            d="$(basename "${obj}" | sed -nE 's/^life-game-([0-9]{8})T.*/\1/p')"
            if [ -n "${d}" ] && [ "${d}" -lt "${cutoff}" ]; then
                log "deleting old backup ${obj}"
                gcloud_run "gcloud storage rm ${obj} -q" || log "could not delete ${obj}"
            fi
        done
    fi
fi

# rclone (optional, e.g. Google Drive)
if [ -n "${BACKUP_TARGET:-}" ]; then
    rclone copy "${file}" "${BACKUP_TARGET}"
    rclone delete "${BACKUP_TARGET}" --min-age "${RETENTION_DAYS}d" --include 'life-game-*.sql.gz'
    log "uploaded to ${BACKUP_TARGET}"
fi

find backups -name 'life-game-*.sql.gz' -mtime "+${RETENTION_DAYS}" -delete
log "backup finished"
