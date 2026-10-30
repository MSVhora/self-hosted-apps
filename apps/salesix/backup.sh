#!/usr/bin/env bash
# Daily Salesix Postgres backup -> gs://<GCS_BACKUP_BUCKET>/<GCS_BACKUP_PATH>/salesix-db-<timestamp>.sql.gz
# Run by /etc/cron.d/salesix-backup (installed by scripts/setup-salesix.sh). Safe to run by hand.
#
# Reads POSTGRES_USER, POSTGRES_DB, GCS_BACKUP_BUCKET and GCS_CREDENTIALS_BASE64 (service-account key,
# base64) from backend.env. gcloud runs in a container, so nothing is installed on the host.
#
# RETENTION_DAYS (default 30): delete bucket backups older than this; 0 turns deletion off.
# LOCAL_KEEP_DAYS (default 3): local copies kept in ./backups.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"

ENV_FILE="backend.env"
CONTAINER="${DB_CONTAINER:-salesix-postgres}"
GCLOUD_IMAGE="${GCLOUD_IMAGE:-gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
LOCAL_KEEP_DAYS="${LOCAL_KEEP_DAYS:-3}"
MIN_BYTES="${MIN_BYTES:-1000000}"   # a real dump is tens of MB; anything this small means something went wrong

log() { echo "[$(date +'%F %T')] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

# KEY=value or KEY="value" # comment -> value
get_env() {
    grep -E "^$1=" "${ENV_FILE}" | head -1 | cut -d= -f2- \
        | sed -E 's/^"([^"]*)".*$/\1/; s/^([^" ]*).*$/\1/'
}

[ -f "${ENV_FILE}" ] || die "${ENV_FILE} not found"
PGUSER="$(get_env POSTGRES_USER)"
PGDB="$(get_env POSTGRES_DB)"
BUCKET="$(get_env GCS_BACKUP_BUCKET)"; BUCKET="${BUCKET:-salesix-db-backups}"
CREDS_B64="$(get_env GCS_CREDENTIALS_BASE64)"
GCS_PATH="${GCS_BACKUP_PATH:-backups}"
[ -n "${PGUSER}" ] && [ -n "${PGDB}" ] || die "POSTGRES_USER / POSTGRES_DB missing in ${ENV_FILE}"
[ -n "${CREDS_B64}" ] || die "GCS_CREDENTIALS_BASE64 missing in ${ENV_FILE}"

mkdir -p "${BACKUP_DIR}"
FILE="salesix-db-$(date +%Y-%m-%d-%H%M%S).sql.gz"
OUT="${BACKUP_DIR}/${FILE}"

# 1. Dump (to a partial file first so a failed run never leaves something that looks valid)
log "Dumping ${PGDB} from ${CONTAINER}"
docker exec "${CONTAINER}" pg_dump -U "${PGUSER}" -d "${PGDB}" --no-owner --no-acl | gzip > "${OUT}.partial" \
    || { rm -f "${OUT}.partial"; die "pg_dump failed"; }
gzip -t "${OUT}.partial" || { rm -f "${OUT}.partial"; die "dump is not valid gzip"; }
SIZE="$(wc -c < "${OUT}.partial" | tr -d ' ')"
[ "${SIZE}" -ge "${MIN_BYTES}" ] || { rm -f "${OUT}.partial"; die "dump only ${SIZE} bytes, refusing to upload"; }
mv "${OUT}.partial" "${OUT}"
log "Dump ok: ${FILE} (${SIZE} bytes)"

# 2. Upload + verify, using a throwaway key file that is deleted on exit
KEY="$(mktemp)"; chmod 600 "${KEY}"
trap 'rm -f "${KEY}"' EXIT
echo "${CREDS_B64}" | base64 -d > "${KEY}" || die "GCS_CREDENTIALS_BASE64 is not valid base64"

GCLOUD() {
    docker run --rm -v "${KEY}:/key.json:ro" -v "$(pwd)/${BACKUP_DIR#./}:/backups:ro" "${GCLOUD_IMAGE}" \
        sh -c 'gcloud auth activate-service-account --key-file=/key.json -q >/dev/null 2>&1 && '"$1"
}

DEST="gs://${BUCKET}/${GCS_PATH}/${FILE}"
log "Uploading to ${DEST}"
GCLOUD "gcloud storage cp /backups/${FILE} ${DEST} -q" || die "upload failed"
REMOTE_SIZE="$(GCLOUD "gcloud storage ls -l ${DEST}" | awk 'NR==1{print $1}')"
[ "${REMOTE_SIZE}" = "${SIZE}" ] || die "uploaded size ${REMOTE_SIZE:-?} does not match local ${SIZE}"
log "Upload verified (${REMOTE_SIZE} bytes)"

# 3. Retention in the bucket (names carry the date: salesix-db-YYYY-MM-DD-HHMMSS.sql.gz)
if [ "${RETENTION_DAYS}" -gt 0 ]; then
    CUTOFF="$(date -u -d "${RETENTION_DAYS} days ago" +%F)"
    log "Removing bucket backups older than ${CUTOFF}"
    GCLOUD "gcloud storage ls gs://${BUCKET}/${GCS_PATH}/" | while read -r obj; do
        d="$(basename "${obj}" | sed -nE 's/^salesix-db-([0-9]{4}-[0-9]{2}-[0-9]{2})-.*/\1/p')"
        if [ -n "${d}" ] && [[ "${d}" < "${CUTOFF}" ]]; then
            log "  deleting ${obj}"
            GCLOUD "gcloud storage rm ${obj} -q" || log "  could not delete ${obj}"
        fi
    done
fi

# 4. Local cleanup
find "${BACKUP_DIR}" -name 'salesix-db-*.sql.gz' -type f -mtime "+${LOCAL_KEEP_DAYS}" -delete
log "Backup finished"
