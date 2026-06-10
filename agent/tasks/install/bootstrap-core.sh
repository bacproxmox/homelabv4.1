#!/usr/bin/env bash
set -Eeuo pipefail
echo "Homelabv4 bootstrap core bridge"

mkdir -p /root/.ssh /root/homelab-secrets /opt/homelabv4/state
chmod 700 /root/.ssh /root/homelab-secrets 2>/dev/null || true
if [[ ! -f /root/.ssh/id_ed25519 ]]; then
  echo "Creating Proxmox root SSH key for VM cloud-init and service orchestration."
  ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519 >/dev/null
fi
touch /root/.ssh/known_hosts
chmod 600 /root/.ssh/known_hosts 2>/dev/null || true

if [[ -x /opt/homelabv4/core/bin/homelab ]]; then
  /opt/homelabv4/core/bin/homelab list || true
else
  echo "Core repo is not available yet. Agent bootstrap attempted git clone during install."
fi
