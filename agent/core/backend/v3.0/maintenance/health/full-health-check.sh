#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "full-health-check"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
source "$ROOT_DIR/utils/state.sh"

health_fail=0
CHIA_DB_BOOTSTRAP_PENDING="$(state_get chia_db_bootstrap_pending 2>/dev/null || echo false)"

echo "Homelab v4.1 full health check"
echo
for vm in 101 102 103 104 105 106 107 110; do
  ip="$(vm_ip "$vm")"
  printf "VM%s %-15s " "$vm" "$ip"
  if ping -c1 -W1 "$ip" >/dev/null 2>&1; then
    echo "OK ping"
  else
    echo "WARN ping missing"
  fi
done

check_http() {
  local name="$1" url="$2"
  if curl -kfsS --max-time 4 "$url" >/dev/null 2>&1; then
    echo "OK $name $url"
  else
    echo "WARN $name no response: $url"
  fi
}

check_http qBittorrent http://192.168.50.102:8080
check_http Sonarr http://192.168.50.102:8989
check_http Radarr http://192.168.50.102:7878
check_http Prowlarr http://192.168.50.102:9696
check_http Bazarr http://192.168.50.102:6767
check_http Seerr http://192.168.50.102:5055
check_http UptimeKuma http://192.168.50.103:3001
check_http Nextcloud http://192.168.50.104:8080/status.php
check_http Jellyfin http://192.168.50.106:8096
check_http Immich http://192.168.50.106:2283
check_http OpenWebUI http://192.168.50.106:3000
check_http HomeAssistant http://192.168.50.105:8123
check_http Lidarr http://192.168.50.106:8686
check_http PBS https://192.168.50.110:8007

for vm in 102 103 104 105 106 107; do
  echo
  echo "VM$vm containers"
  rssh "$vm" "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true" || true
done

echo
echo "Nextcloud tank data mount"
rssh 104 'docker exec hb-nextcloud test -f /var/www/html/version.php && echo version.php OK || true; docker exec hb-nextcloud df -h /var/www/html/data 2>/dev/null || true' || true

echo
echo "VM106 /dev/dri/i915"
rssh 106 'ls -lah /dev/dri 2>/dev/null || true; lspci -nnk | grep -A3 -Ei "UHD Graphics|i915" || true' || true

echo
echo "VM107 Chia repair preflight"
if [[ -x "$ROOT_DIR/maintenance/repair/repair-chia-plot-disks.sh" ]]; then
  if ! HOMELAB_CHIA_NO_START="$([[ "$CHIA_DB_BOOTSTRAP_PENDING" == "true" ]] && echo 1 || echo 0)" bash "$ROOT_DIR/maintenance/repair/repair-chia-plot-disks.sh"; then
    echo "WARN VM107 Chia plot disk repair returned non-zero; continuing with health diagnostics."
    health_fail=1
  fi
else
  echo "WARN Chia plot disk repair script is missing."
fi

echo
echo "VM107 Chia health"
CHIA_EXPECTED_REMOTE="${EXPECTED_CHIA_PLOT_DISKS:-5}"
if [[ "$CHIA_DB_BOOTSTRAP_PENDING" == "true" ]]; then
  echo "WARN Chia DB bootstrap is pending; Chia farmer service and NVIDIA runtime checks are advisory until the DB bootstrap/start button runs."
fi
if ! rssh 107 "EXPECTED_CHIA_PLOT_DISKS='$CHIA_EXPECTED_REMOTE' CHIA_DB_BOOTSTRAP_PENDING='$CHIA_DB_BOOTSTRAP_PENDING' bash -s" <<'REMOTECHIA'
set +e
status=0
expected=${EXPECTED_CHIA_PLOT_DISKS:-5}
pending=${CHIA_DB_BOOTSTRAP_PENDING:-false}

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  echo "OK nvidia-smi"
else
  if [[ "$pending" == "true" ]]; then
    echo "WARN nvidia-smi missing or NVIDIA driver is not ready; Chia DB bootstrap is pending"
  else
    echo "FAIL nvidia-smi missing or NVIDIA driver is not ready"
    status=1
  fi
fi

if [[ -x /opt/chia-blockchain/venv/bin/chia ]]; then
  echo "OK Chia binary: /opt/chia-blockchain/venv/bin/chia"
elif command -v chia >/dev/null 2>&1; then
  echo "OK Chia binary: $(command -v chia)"
else
  echo "FAIL Chia binary missing: /opt/chia-blockchain/venv/bin/chia"
  status=1
fi

if systemctl is-active --quiet chia-farmer.service; then
  echo "OK chia-farmer.service active"
else
  if [[ "$pending" == "true" ]]; then
    echo "WARN chia-farmer.service is intentionally stopped until DB bootstrap/start"
  else
    echo "WARN chia-farmer.service is not active"
  fi
fi

mounted=$(findmnt -rn -o TARGET | grep -E '^/mnt/chia-plots/disk[0-9]+$' | sort -V | wc -l)
echo "mounted plot disks=${mounted} / expected=${expected}"
if [ "$mounted" -lt "$expected" ]; then
  echo "FAIL expected ${expected} plot disks; mounted ${mounted}"
  status=1
  echo "--- fstab chia entries ---"
  grep -E '/mnt/chia-plots/disk[0-9]+' /etc/fstab || true
  echo "--- mounted chia targets ---"
  findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS | grep -E '/mnt/chia-plots/disk[0-9]+' || true
  echo "--- candidate block devices ---"
  lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,LABEL,MOUNTPOINT | grep -Ei 'TOSHIBA|chia|/mnt/chia-plots|disk' || true
  echo "--- disk serial map ---"
  find /dev/disk/by-id -maxdepth 1 -type l | grep -Ei 'TOSHIBA_HDWG|HDWG180|HDWG480' | sort || true
  echo "--- recent VM107 SATA/JMicron disk errors ---"
  dmesg -T 2>/dev/null | grep -Ei 'ata|reset|I/O error|failed command|TOSHIBA|JMicron|JMB|JMS' | tail -80 || true
else
  echo "OK Chia plot mounts"
  findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS | grep -E '/mnt/chia-plots/disk[0-9]+' || true
fi

df -h | grep /mnt/chia-plots || true
grep -R "parallel_decompressor_count" ~/.chia/mainnet/config/config.yaml 2>/dev/null || true
ss -ltnp | grep 55400 || true
exit "$status"
REMOTECHIA
then
  health_fail=1
fi

if [[ "$health_fail" -ne 0 ]]; then
  echo
  echo "FULL_HEALTH_NEEDS_ATTENTION: VM107 Chia hardware/service checks need attention."
  exit 1
fi

echo
echo "Full health check completed."
