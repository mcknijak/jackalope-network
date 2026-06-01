#!/usr/bin/env bash
#
# One-shot bootstrap for a fresh Debian 13 (Trixie) install.
# Also runs fine on Debian 12 (Bookworm); the Docker apt line resolves
# the codename from /etc/os-release at install time.
# Run as root: sudo bash bootstrap/debian-setup.sh
#
# Idempotent where it can be. Re-running should be safe.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Must run as root." >&2
  exit 1
fi

# Edit these to match your install.
NEW_USER="${NEW_USER:-jack}"
HOSTNAME="${HOSTNAME:-jackalope}"

echo ">>> Setting hostname to ${HOSTNAME}"
hostnamectl set-hostname "${HOSTNAME}"

echo ">>> apt update + upgrade"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

echo ">>> Installing baseline packages"
apt-get install -y \
  ca-certificates curl gnupg lsb-release \
  ufw fail2ban unattended-upgrades \
  mdadm smartmontools \
  restic \
  htop iotop ncdu vim git tmux \
  rsync jq

echo ">>> Configuring unattended security upgrades"
dpkg-reconfigure -plow unattended-upgrades || true

echo ">>> Ensuring user ${NEW_USER} exists"
if ! id -u "${NEW_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "${NEW_USER}"
fi
usermod -aG sudo "${NEW_USER}"

echo ">>> SSH hardening"
SSHD=/etc/ssh/sshd_config.d/99-homelab.conf
cat > "${SSHD}" <<'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
EOF
systemctl reload ssh || systemctl reload sshd

echo ">>> UFW (deny inbound by default, allow ssh + tailscale)"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow in on tailscale0
ufw --force enable

echo ">>> Installing Docker (official repo)"
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
fi
if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
    > /etc/apt/sources.list.d/docker.list
fi
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

usermod -aG docker "${NEW_USER}"
systemctl enable --now docker

echo ">>> Installing Tailscale"
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
systemctl enable --now tailscaled

echo ">>> Creating shared Docker proxy network (idempotent)"
if ! docker network inspect proxy >/dev/null 2>&1; then
  docker network create proxy
fi

echo ">>> Creating /srv tree"
install -d -o "${NEW_USER}" -g "${NEW_USER}" /srv

echo
echo "Bootstrap complete."
echo
echo "Next steps depend on which stage you are at (see docs/staged-rollout.md):"
echo
echo "  All stages:"
echo "    a. Run: sudo tailscale up"
echo "    b. Clone this repo's stacks into /srv/."
echo
echo "  Stage 1 (PC only, no extra storage):"
echo "    c. Create the per-app data dirs on the OS disk."
echo "       Cabinet (Paperless) is stage 2+ only and is skipped here:"
echo "       sudo mkdir -p /mnt/data/{immich/library,immich/postgres,jellyfin/movies,\\"
echo "                              jellyfin/shows,jellyfin/music,couchdb/data,couchdb/config,\\"
echo "                              matrix/synapse,matrix/postgres,matrix/media,\\"
echo "                              ebooks/library,ebooks/config,\\"
echo "                              spokenword/audiobooks,spokenword/podcasts,\\"
echo "                              spokenword/metadata,spokenword/config,\\"
echo "                              portainer/data,\\"
echo "                              backups}"
echo "       sudo chown -R \${USER}:\${USER} /mnt/data"
echo "    d. Bring up each app stack under /srv/ (immich, jellyfin, obsidian-couchdb,"
echo "       matrix, ebooks, spokenword, portainer). Cabinet waits until stage 2."
echo
echo "  Stage 2 (PC + one extra drive + B2):"
echo "    c. Plug in and LUKS-format the extra drive; mount it at /mnt/data."
echo "    d. Create the per-app subdirectories on /mnt/data. Same as stage 1 plus"
echo "       cabinet (which comes online at stage 2):"
echo "       sudo mkdir -p /mnt/data/cabinet/{data,media,consume,export,postgres}"
echo "       sudo chown -R \${USER}:\${USER} /mnt/data/cabinet"
echo "    e. Bring up each app stack under /srv/, now including cabinet."
echo "    f. Set up B2 backups (backups/README.md, B2 half only)."
echo
echo "  Stage 3 (PC + RAID1 mirror + full backup):"
echo "    c. Plug in both NAS drives, run:"
echo "       sudo bash bootstrap/mdadm-mirror.sh /dev/sdX /dev/sdY"
echo "       (this creates the mirror, LUKS-formats it, mounts at /mnt/data,"
echo "        and creates the per-app subdirectories including cabinet)."
echo "    d. Plug in the USB backup drive; format ext4 and mount at /mnt/backup."
echo "    e. Bring up each app stack under /srv/."
echo "    f. Set up restic backups (backups/README.md, both USB and B2)."
