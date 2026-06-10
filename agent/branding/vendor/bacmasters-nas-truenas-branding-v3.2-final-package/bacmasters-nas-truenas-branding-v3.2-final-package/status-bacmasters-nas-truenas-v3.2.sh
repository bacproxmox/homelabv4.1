#!/usr/bin/env bash
set -Eeuo pipefail

# Quick status checker for Bacmaster's NAS TrueNAS WebUI branding.
# Run on Proxmox as root.

TRUENAS_IP="${TRUENAS_IP:-192.168.50.101}"
source /root/homelab-secrets/truenas-login.env 2>/dev/null || true
TRUENAS_USER="${TRUENAS_SSH_USER:-truenas_admin}"
TRUENAS_PASS="${TRUENAS_SSH_PASS:-}"

if [[ -z "$TRUENAS_PASS" ]]; then
  echo "TrueNAS SSH/sudo password gerekli."
  read -rsp "TrueNAS password: " TRUENAS_PASS
  echo
fi

if ! command -v sshpass >/dev/null 2>&1; then
  apt-get update && apt-get install -y sshpass
fi

{
  printf '%s\n' "$TRUENAS_PASS"
  cat <<'REMOTE'
set -Eeuo pipefail
WEBUI="/usr/share/truenas/webui"
INDEX="$WEBUI/index.html"
BRAND="$WEBUI/bacmasters-brand"

echo "TrueNAS version:"
cat /etc/version 2>/dev/null || true

echo
echo "Branding injection:"
if grep -q 'BACMASTERS_NAS_BRANDING_START' "$INDEX" 2>/dev/null; then
  echo "  index.html: present"
else
  echo "  index.html: missing"
fi

echo
echo "Assets:"
for f in \
  "$BRAND/bacmasters-nas-branding.js" \
  "$BRAND/bacmasters-nas-branding.css" \
  "$BRAND/bacmasters-nas-logo-transparent.png" \
  "$BRAND/bacmasters-nas-login-background.png"
do
  if [[ -f "$f" ]]; then
    echo "  OK: $f"
  else
    echo "  MISSING: $f"
  fi
done

echo
echo "Backups:"
find /root/bacmasters-nas-webui-backups -maxdepth 1 -type d 2>/dev/null | sort | tail -10 || true

echo
echo "Mountpoints:"
for p in / /usr /usr/share "$WEBUI"; do
  findmnt -T "$p" -no TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || true
done | awk '!seen[$0]++'
REMOTE
} | SSHPASS="$TRUENAS_PASS" sshpass -e ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "$TRUENAS_USER@$TRUENAS_IP" \
  "sudo -S -p '' bash -s"
