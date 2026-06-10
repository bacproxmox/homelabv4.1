#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "full-service-audit"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

check_vm(){
  local vm="$1" name="$2"
  echo
  echo "================ VM$vm $name ================"
  if rssh "$vm" "hostname" >/dev/null 2>&1; then
    rssh "$vm" "hostname; uptime; echo; docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true; echo; df -h | grep -E '/mnt|Filesystem' || true"
  else
    echo "❌ VM $vm SSH erişilemiyor"
  fi
}
check_vm 102 docker-arr
check_vm 103 docker-network
check_vm 104 nextcloud
check_vm 105 homeassistant
check_vm 106 media-ai
check_vm 107 chia-farmer
check_vm 110 pbs-backup

echo
 echo "================ SPECIAL SERVICE CHECKS ================"
rssh 104 'echo "Nextcloud:"; docker exec hb-nextcloud test -f /var/www/html/version.php && echo version.php OK || true; docker exec hb-nextcloud df -h /var/www/html/data 2>/dev/null || true; docker exec -u www-data hb-nextcloud php occ config:system:get mail_smtpmode 2>/dev/null || true' || true
rssh 106 'echo "Jellyfin GPU:"; ls -lah /dev/dri 2>/dev/null || true; docker exec hb-jellyfin ls -lah /dev/dri 2>/dev/null || true; echo "Immich upload:"; docker inspect hb-immich-server --format "{{json .Mounts}}" 2>/dev/null | jq "." 2>/dev/null | grep -E "immich-upload|/usr/src/app/upload|/mnt/tank/photos" || true' || true
rssh 110 'echo "PBS:"; systemctl is-active proxmox-backup-proxy || true; ss -ltnp | grep 8007 || true; if command -v proxmox-backup-manager >/dev/null 2>&1; then proxmox-backup-manager version || true; else dpkg-query -W proxmox-backup-server 2>/dev/null || true; fi; apt-cache policy proxmox-backup-server 2>/dev/null | sed -n "1,20p" || true' || true

rssh 107 'echo "Chia:"; command -v chia || true; ss -ltnp | grep 55400 || true; grep -R "parallel_decompressor_count" ~/.chia/mainnet/config/config.yaml 2>/dev/null || true; df -h | grep /mnt/chia-plots || true; find /mnt/chia-plots/disk* -maxdepth 1 -type f -name "*.plot" 2>/dev/null | wc -l' || true

echo
 echo "================ LAN PORT CHECK ================"
for item in \
  "192.168.50.102 8080 qbittorrent" \
  "192.168.50.102 8989 sonarr" \
  "192.168.50.102 7878 radarr" \
  "192.168.50.102 9696 prowlarr" \
  "192.168.50.102 6767 bazarr" \
  "192.168.50.102 5055 seerr" \
  "192.168.50.103 3001 uptime-kuma" \
  "192.168.50.104 8080 nextcloud" \
  "192.168.50.106 8096 jellyfin" \
  "192.168.50.106 2283 immich" \
  "192.168.50.106 3000 openwebui" \
  "192.168.50.105 8123 homeassistant" \
  "192.168.50.106 8686 lidarr" \
  "192.168.50.110 8007 pbs"; do
  set -- $item
  host="$1"; port="$2"; name="$3"
  if timeout 3 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then echo "✅ $name $host:$port açık"; else echo "❌ $name $host:$port kapalı/erişilemedi"; fi
done
