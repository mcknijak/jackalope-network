#!/usr/bin/env bash
#
# restic backup runner.
# Called by systemd timers as: restic-backup.sh {usb|b2}
#
# Reads credentials and repo URLs from /etc/restic.env.

set -euo pipefail

TARGET="${1:-}"
case "$TARGET" in
  usb|b2) ;;
  *)
    echo "Usage: $0 {usb|b2}" >&2
    exit 1
    ;;
esac

# /etc/restic.env defines:
#   RESTIC_PASSWORD
#   RESTIC_REPOSITORY_USB
#   RESTIC_REPOSITORY_B2
#   B2_ACCOUNT_ID
#   B2_ACCOUNT_KEY
set -a
# shellcheck disable=SC1091
source /etc/restic.env
set +a

if [[ "$TARGET" == "usb" ]]; then
  export RESTIC_REPOSITORY="$RESTIC_REPOSITORY_USB"
else
  export RESTIC_REPOSITORY="$RESTIC_REPOSITORY_B2"
fi

LOG_TAG="restic-${TARGET}"
log() { logger -t "$LOG_TAG" "$*"; echo "[$LOG_TAG] $*"; }

DUMP_DIR=$(mktemp -d /tmp/restic-dumps.XXXXXX)
trap 'rm -rf "$DUMP_DIR"' EXIT

log "Dumping Postgres databases"

# Immich Postgres
docker exec immich_postgres pg_dump -U postgres -Fc immich \
  > "$DUMP_DIR/immich.pgdump"

# Synapse Postgres
docker exec synapse_postgres pg_dump -U synapse -Fc synapse \
  > "$DUMP_DIR/synapse.pgdump"

# Paperless Postgres (cabinet stack; only runs at stage 2+)
if docker ps --format '{{.Names}}' | grep -q '^paperless-db$'; then
  docker exec paperless-db pg_dump -U paperless -Fc paperless \
    > "$DUMP_DIR/paperless.pgdump"
else
  log "paperless-db not running; skipping paperless pg_dump (expected pre-stage-2)"
fi

# CouchDB: replicate _all_dbs to flat JSON snapshots. The on-disk
# .couch files are also captured below via /mnt/data/couchdb, but
# a logical export is easier to restore selectively.
log "Snapshotting CouchDB databases"
COUCH_AUTH=$(grep -E '^COUCHDB_(USER|PASSWORD)=' /srv/obsidian-couchdb/.env \
  | sed 's/^[^=]*=//' | paste -sd: -)
docker exec couchdb \
  curl -fsS "http://${COUCH_AUTH}@127.0.0.1:5984/_all_dbs" \
  > "$DUMP_DIR/couch-all-dbs.json" || log "warning: couch _all_dbs snapshot failed"

log "Running restic backup against $RESTIC_REPOSITORY"

restic backup \
  --tag "$TARGET" \
  --tag homelab \
  --exclude-caches \
  --exclude "/mnt/data/jellyfin" \
  /mnt/data/immich \
  /mnt/data/couchdb \
  /mnt/data/matrix \
  /mnt/data/ebooks \
  /mnt/data/spokenword \
  /mnt/data/cabinet \
  /mnt/data/portainer \
  /srv \
  "$DUMP_DIR"

# Note: /mnt/data/cabinet and /mnt/data/portainer paths simply do not exist
# until the relevant stack is deployed (cabinet at stage 2, portainer at
# stage 1). restic will warn but proceed when a listed path is missing.

log "Forgetting old snapshots and pruning"

# Retention: more recent snapshots on USB (closer at hand),
# fewer on B2 (where storage is metered).
if [[ "$TARGET" == "usb" ]]; then
  restic forget --prune \
    --keep-daily 14 \
    --keep-weekly 8 \
    --keep-monthly 12
else
  restic forget --prune \
    --keep-weekly 4 \
    --keep-monthly 12 \
    --keep-yearly 3
fi

log "Done"
