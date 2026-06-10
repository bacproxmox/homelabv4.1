#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "docker-cleanup"
source "$ROOT_DIR/utils/remote.sh"

echo "🧹 Docker cleanup remote VM'lerde çalışacak: 102 103 104 105 106 107"
read -r -p "Devam edilsin mi? YES yaz: " ok
[[ "$ok" == "YES" ]] || { echo "İptal."; exit 0; }
for vm in 102 103 104 105 106 107; do
  echo "▶️ VM$vm docker cleanup"
  rssh "$vm" "sudo docker system prune -f || true; sudo docker volume prune -f || true"
done
