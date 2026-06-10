#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "repair-nfs-mounts"
source "$ROOT_DIR/utils/remote.sh"

for vm in 102 104 106; do
  echo "▶️ VM$vm mount repair"
  rssh "$vm" "sudo systemctl daemon-reload; sudo mount -a || true; df -h | egrep 'Filesystem|/mnt' || true" || true
done

echo "☁️ Nextcloud NFS permission preflight"
rssh 104 'sudo bash -lc "mkdir -p /mnt/nextcloud/data; mountpoint -q /mnt/nextcloud && chown 33:33 /mnt/nextcloud/data && chmod 750 /mnt/nextcloud/data && echo OK || echo FAIL; df -h /mnt/nextcloud /mnt/nextcloud/data 2>/dev/null || true"' || true

echo "📸 Immich photo mounts"
rssh 106 'df -h /mnt/tank/photos /mnt/private/photos 2>/dev/null || true' || true

echo "🌱 Chia plot disk mounts"
rssh 107 'df -h | grep /mnt/chia-plots || true; find /dev/disk/by-id -maxdepth 1 -type l | grep -Ei "TOSHIBA_HDWG|HDWG180|HDWG480" | sort || true' || true
