#!/usr/bin/env bash
# Replaces the Life Game database with a gzipped dump. DESTROYS the current data.
# Usage: ./restore.sh path/to/life-game-XXXX.sql.gz
set -euo pipefail
cd "$(dirname "$0")"
DUMP="${1:?usage: ./restore.sh <dump.sql.gz>}"
[ -f "$DUMP" ] || { echo "no such file: $DUMP" >&2; exit 1; }
set -a; . ./.env; set +a
DBU="${POSTGRES_USER:-life}"; DBN="${POSTGRES_DB:-life}"

read -r -p "This replaces all data in database '$DBN'. Type 'restore' to continue: " answer
[ "$answer" = "restore" ] || { echo "aborted"; exit 1; }

docker compose up -d db
docker compose stop app >/dev/null 2>&1 || true
docker compose exec -T db psql -U "$DBU" -d postgres -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE IF EXISTS \"$DBN\" WITH (FORCE)" -c "CREATE DATABASE \"$DBN\""
gunzip -c "$DUMP" | docker compose exec -T db psql -U "$DBU" -d "$DBN" -v ON_ERROR_STOP=1 -q
docker compose up -d app
echo "restored from $DUMP"
