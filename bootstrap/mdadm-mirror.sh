#!/usr/bin/env bash
#
# Create a RAID1 mirror over two block devices, format ext4,
# mount at /mnt/data, and create the per-app subdirectories.
#
# Usage:  sudo bash bootstrap/mdadm-mirror.sh /dev/sdX /dev/sdY
#
# DESTRUCTIVE: both devices will be wiped.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Must run as root." >&2
  exit 1
fi

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 /dev/sdX /dev/sdY" >&2
  exit 1
fi

DEV1="$1"
DEV2="$2"
MD=/dev/md0
MOUNT=/mnt/data
OWNER_USER="${OWNER_USER:-jack}"

for d in "$DEV1" "$DEV2"; do
  if [[ ! -b "$d" ]]; then
    echo "Not a block device: $d" >&2
    exit 1
  fi
done

cat <<EOF

About to:
  - WIPE ${DEV1} and ${DEV2}
  - Create RAID1 mirror at ${MD}
  - Format ext4
  - Mount at ${MOUNT}
  - Persist in /etc/fstab via UUID

EOF
read -r -p "Type YES to continue: " confirm
if [[ "$confirm" != "YES" ]]; then
  echo "Aborted."
  exit 1
fi

echo ">>> Zeroing superblocks (in case the devices were previously part of an array)"
mdadm --zero-superblock --force "$DEV1" "$DEV2" || true
wipefs -a "$DEV1" "$DEV2"

echo ">>> Creating mirror"
mdadm --create "$MD" --level=1 --raid-devices=2 --metadata=1.2 "$DEV1" "$DEV2"

echo ">>> Persisting mdadm config"
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
update-initramfs -u

echo ">>> Formatting ext4"
mkfs.ext4 -L homelab-data "$MD"

echo ">>> Mounting at ${MOUNT}"
mkdir -p "$MOUNT"
UUID=$(blkid -s UUID -o value "$MD")
if ! grep -q "$UUID" /etc/fstab; then
  echo "UUID=${UUID} ${MOUNT} ext4 defaults,nofail 0 2" >> /etc/fstab
fi
mount -a

echo ">>> Creating app subdirectories"
install -d -o "$OWNER_USER" -g "$OWNER_USER" \
  "${MOUNT}/immich/library" \
  "${MOUNT}/immich/postgres" \
  "${MOUNT}/jellyfin/movies" \
  "${MOUNT}/jellyfin/shows" \
  "${MOUNT}/jellyfin/music" \
  "${MOUNT}/couchdb/data" \
  "${MOUNT}/couchdb/config" \
  "${MOUNT}/matrix/media" \
  "${MOUNT}/matrix/postgres" \
  "${MOUNT}/matrix/synapse" \
  "${MOUNT}/backups"

echo ">>> Done. Mirror status:"
cat /proc/mdstat

echo
echo "Initial sync runs in the background and can take several hours."
echo "Check progress any time with: cat /proc/mdstat"
