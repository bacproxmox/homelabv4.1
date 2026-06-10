#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "repair-docker-permissions"
source "$ROOT_DIR/utils/remote.sh"
for vm in 102 103 104 106 107; do
  echo "▶️ VM$vm docker permission repair"
  rssh "$vm" "sudo usermod -aG docker ${BACMASTER_USER:-bacmaster} || true; sudo chown -R ${MEDIA_UID:-1000}:${MEDIA_GID:-1000} /opt/homelab /mnt/media /mnt/photos 2>/dev/null || true"
done
