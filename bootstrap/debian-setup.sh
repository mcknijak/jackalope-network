#!/usr/bin/env bash
#
# One-shot bootstrap for a fresh Debian 12 install.
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
echo "Next steps:"
echo "  1. Run: sudo tailscale up"
echo "  2. Plug in HDDs, run: sudo bootstrap/mdadm-mirror.sh /dev/sdX /dev/sdY"
echo "  3. Clone this repo's stacks into /srv/, then bring up each app."
