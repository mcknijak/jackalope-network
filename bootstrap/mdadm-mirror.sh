#!/usr/bin/env bash
#
# Create a RAID1 mirror over two block devices, optionally wrap it in
# LUKS, format ext4, mount at /mnt/data, and create the per-app
# subdirectories.
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
MAPPER_NAME=data-crypt
MAPPER_PATH="/dev/mapper/${MAPPER_NAME}"
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
  - Optionally wrap the mirror in LUKS
  - Format ext4
  - Mount at ${MOUNT}
  - Persist in /etc/fstab (and /etc/crypttab if LUKS)

EOF
read -r -p "Type YES to continue: " confirm
if [[ "$confirm" != "YES" ]]; then
  echo "Aborted."
  exit 1
fi

echo
echo "Encrypt the mirror with LUKS?"
echo "  Recommended for any data you would not want read off a stolen drive."
echo "  After enabling, every reboot needs an interactive unlock over SSH."
echo "  See docs/encryption-at-rest.md for the post-reboot procedure."
echo
read -r -p "Enable LUKS on the mirror? [y/N]: " use_luks_raw
USE_LUKS=no
if [[ "${use_luks_raw,,}" == "y" || "${use_luks_raw,,}" == "yes" ]]; then
  USE_LUKS=yes
  if ! command -v cryptsetup >/dev/null; then
    echo ">>> Installing cryptsetup"
    apt-get update
    apt-get install -y cryptsetup
  fi
fi

echo ">>> Zeroing superblocks (in case the devices were previously part of an array)"
mdadm --zero-superblock --force "$DEV1" "$DEV2" || true
wipefs -a "$DEV1" "$DEV2"

echo ">>> Creating mirror"
mdadm --create "$MD" --level=1 --raid-devices=2 --metadata=1.2 "$DEV1" "$DEV2"

echo ">>> Persisting mdadm config"
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
update-initramfs -u

if [[ "$USE_LUKS" == "yes" ]]; then
  echo ">>> Formatting LUKS on the mirror"
  echo "    You will be prompted for the LUKS passphrase twice."
  echo "    Pick a strong one. Store it in your password manager."
  cryptsetup luksFormat --type luks2 --pbkdf argon2id "$MD"

  echo ">>> Opening the LUKS container as ${MAPPER_NAME}"
  cryptsetup open "$MD" "$MAPPER_NAME"

  FS_TARGET="$MAPPER_PATH"
else
  FS_TARGET="$MD"
fi

echo ">>> Formatting ext4 on ${FS_TARGET}"
mkfs.ext4 -L homelab-data "$FS_TARGET"

echo ">>> Mounting at ${MOUNT}"
mkdir -p "$MOUNT"

if [[ "$USE_LUKS" == "yes" ]]; then
  LUKS_UUID=$(blkid -s UUID -o value "$MD")
  FS_UUID=$(blkid -s UUID -o value "$MAPPER_PATH")

  if ! grep -q "$LUKS_UUID" /etc/crypttab 2>/dev/null; then
    # noauto: do not try to unlock at boot. Operator unlocks manually after reboot.
    echo "${MAPPER_NAME} UUID=${LUKS_UUID} none luks,noauto" >> /etc/crypttab
  fi

  if ! grep -q "$FS_UUID" /etc/fstab; then
    # noauto plus nofail: do not block boot if the mapper is not opened yet.
    echo "UUID=${FS_UUID} ${MOUNT} ext4 defaults,noauto,nofail 0 2" >> /etc/fstab
  fi
  mount "$MOUNT"
else
  FS_UUID=$(blkid -s UUID -o value "$MD")
  if ! grep -q "$FS_UUID" /etc/fstab; then
    echo "UUID=${FS_UUID} ${MOUNT} ext4 defaults,nofail 0 2" >> /etc/fstab
  fi
  mount -a
fi

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
  "${MOUNT}/ebooks/library" \
  "${MOUNT}/ebooks/config" \
  "${MOUNT}/spokenword/audiobooks" \
  "${MOUNT}/spokenword/podcasts" \
  "${MOUNT}/spokenword/metadata" \
  "${MOUNT}/spokenword/config" \
  "${MOUNT}/cabinet/data" \
  "${MOUNT}/cabinet/media" \
  "${MOUNT}/cabinet/consume" \
  "${MOUNT}/cabinet/export" \
  "${MOUNT}/cabinet/postgres" \
  "${MOUNT}/portainer/data" \
  "${MOUNT}/backups"

echo ">>> Done. Mirror status:"
cat /proc/mdstat

echo
echo "Initial sync runs in the background and can take several hours."
echo "Check progress any time with: cat /proc/mdstat"

if [[ "$USE_LUKS" == "yes" ]]; then
  cat <<EOF

>>> LUKS is enabled on ${MD}.

After every reboot, /mnt/data will NOT mount automatically. SSH in
and run:

    sudo cryptsetup open ${MD} ${MAPPER_NAME}
    sudo mount ${MOUNT}
    for svc in /srv/*/; do (cd "\$svc" && docker compose up -d); done

Full procedure: docs/encryption-at-rest.md.

EOF
fi
