#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HOMELAB_ROOT/lib/core/runner.sh"

echo
echo "Homelab v3.1.1 - Hardware preflight"
echo "Bu kontrol kurulumdan once SMART/NVMe/isi/kablo sinyallerini ozetler."
echo "Uyari varsa kurulum otomatik durmaz; disk uyarilari ciddiye alinmali."

warn=0
homelab_run "tasks/maintenance/health/nvme-health.sh" || warn=1
homelab_run "tasks/maintenance/health/disk-smart-health.sh" || warn=1
homelab_run "tasks/maintenance/health/disk-temperature.sh" || warn=1
homelab_run "tasks/maintenance/health/kernel-disk-errors.sh" || warn=1

echo
if [[ "$warn" -eq 1 ]]; then
  echo "Hardware preflight uyarili tamamlandi."
  exit 1
fi
echo "Hardware preflight kritik uyari yakalamadi."
