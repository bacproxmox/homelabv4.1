#!/usr/bin/env bash
set -Eeuo pipefail
VMID="${1:-}"
if [[ -z "$VMID" ]]; then echo "Kullanım: $0 <vmid>"; exit 1; fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../utils/logging.sh"
start_log "reset-vm-${VMID}-ubuntu-only"

case "$VMID" in 102|103|104|105|106|107) ;; *) echo "❌ Bu script sadece Ubuntu VM'ler için: 102-107"; exit 1;; esac

read -r -p "VM $VMID içindeki Docker/servis verileri silinsin mi? Ubuntu kalacak. Yaz: RESET-${VMID}: " confirm
[[ "$confirm" == "RESET-${VMID}" ]] || { echo "İptal."; exit 0; }

IP="192.168.50.${VMID}"
USER="bacmaster"
ssh -o StrictHostKeyChecking=no "$USER@$IP" 'sudo bash -s' <<'REMOTE'
set -Eeuo pipefail
systemctl stop docker || true
find /opt/homelab -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true
docker rm -f $(docker ps -aq) 2>/dev/null || true
docker volume rm $(docker volume ls -q) 2>/dev/null || true
docker network rm homelab 2>/dev/null || true
docker system prune -af --volumes || true
mkdir -p /opt/homelab
systemctl start docker || true
docker network create homelab || true
REMOTE

echo "✅ VM $VMID Ubuntu-only reset tamamlandı."
