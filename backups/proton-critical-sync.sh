#!/usr/bin/env bash
#
# Optional supplementary backup: rclone a hand-curated set of "if everything
# else is on fire" files to Proton Drive.
#
# Not a restic repo. Plain encrypted-at-Proton copies, so a restore is just
# "log into Proton Drive in a browser and download the file." This is the
# nuclear-option backup, for the case where B2 is unreachable AND the USB
# drive is unreachable AND restic itself has become an obstacle.
#
# B2 remains the primary offsite. See docs/decisions.md (Proton Drive vs B2)
# for why this is supplementary rather than a replacement.
#
# Prereqs:
#   1. rclone installed (`apt install rclone`)
#   2. rclone remote named "proton" configured: `rclone config` -> new remote
#      -> "protondrive" -> log in with Proton credentials (incl. 2FA token).
#      Config lands at /root/.config/rclone/rclone.conf when run as root.
#   3. A target folder exists in Proton Drive at the path below
#      (default: /HomelabCritical/). Create it via the Proton Drive web UI
#      so rclone has somewhere to write.
#
# Run as root: sudo bash backups/proton-critical-sync.sh

set -euo pipefail

REMOTE="${REMOTE:-proton:HomelabCritical}"
LOG_TAG="proton-critical-sync"

log() { logger -t "$LOG_TAG" "$*"; echo "[$LOG_TAG] $*"; }

# The curated set. Keep this small. Goal: enough to rebuild the box from
# scratch and recover the irreplaceable user data, NOT a full mirror.
# Bootstrap scripts, runbooks, and per-app docs all live under /srv via
# the repo clone at /srv/homelab-server, so /srv captures them too.
SOURCES=(
  # Obsidian notes (small, irreplaceable, the highest-value dataset on the box)
  /mnt/data/couchdb

  # Paperless export directory if cabinet is deployed. Paperless writes a
  # portable export here when you run `document_exporter`; if you haven't
  # set that up, this directory is empty and the copy is a no-op.
  /mnt/data/cabinet/export

  # All compose files, env files, Caddyfile, the bootstrap scripts and
  # docs (the repo clone at /srv/homelab-server), and the welcome site
  # source. Lets a fresh box come back up without reaching for GitHub.
  /srv
)

STAGING=$(mktemp -d /tmp/proton-critical.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT

log "Staging curated tree at $STAGING"

for src in "${SOURCES[@]}"; do
  if [[ ! -e "$src" ]]; then
    log "skip (missing): $src"
    continue
  fi
  # Preserve the absolute path inside the staging dir so the layout in
  # Proton mirrors the layout on the box. Makes restores obvious.
  dest_parent="$STAGING$(dirname "$src")"
  mkdir -p "$dest_parent"
  cp -a "$src" "$dest_parent/"
done

# Tag the snapshot with a timestamp so previous runs can be distinguished
# in the Proton Drive UI. rclone sync with --backup-dir would also work
# but is harder to reason about in a web UI restore.
STAMP=$(date -u +%Y-%m-%dT%H-%M-%SZ)

log "Syncing to ${REMOTE}/${STAMP}"

# --transfers 2 and --tpslimit 4 are conservative settings to stay under
# Proton's rate-limit threshold. Heavier values get throttled or 422'd.
rclone copy "$STAGING" "${REMOTE}/${STAMP}" \
  --transfers 2 \
  --tpslimit 4 \
  --retries 5 \
  --low-level-retries 10 \
  --stats 30s \
  --log-level INFO

# Keep the last 8 weekly snapshots in Proton. Older directories get deleted.
# Proton's quota is the binding constraint, not retention preference.
log "Pruning Proton snapshots older than the last 8"
KEEP=8
mapfile -t SNAPS < <(rclone lsf "${REMOTE}/" --dirs-only | sort -r)
if (( ${#SNAPS[@]} > KEEP )); then
  for old in "${SNAPS[@]:KEEP}"; do
    log "purge ${REMOTE}/${old%/}"
    rclone purge "${REMOTE}/${old%/}"
  done
fi

log "Done"
