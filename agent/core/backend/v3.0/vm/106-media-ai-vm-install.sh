#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/utils/logging.sh"
start_log "vm-106-docker-media"
source "$REPO_ROOT/lib/vm-cloudinit-common.sh"

MEDIA_VM_STORAGE="${MEDIA_VM_STORAGE:-nvme-vm-two}"
VM106_DISK_SIZE="${VM106_DISK_SIZE:-512G}"
VM106_RAM_MB="${VM106_RAM_MB:-65536}"
VM106_BALLOON_MB="${VM106_BALLOON_MB:-32768}"
VM106_ZRAM_MB="${VM106_ZRAM_MB:-8192}"
VM106_CORES="${VM106_CORES:-8}"
export VM106_BALLOON_MB VM106_ZRAM_MB
if ! pvesm status 2>/dev/null | awk '{print $1}' | grep -qx "$MEDIA_VM_STORAGE"; then
  echo "❌ VM106 için storage bulunamadı: $MEDIA_VM_STORAGE"
  echo "v2.4.6 standardı: MLD M500 NVMe üzerinde nvme-vm-two oluşturulmalı."
  echo "Önce Install Menu -> 12 Normalize Proxmox local storage çalıştır."
  exit 1
fi
VM_STORAGE="$MEDIA_VM_STORAGE"
export VM_STORAGE

find_intel_igpu() {
  lspci -Dnn | awk '/VGA compatible controller|Display controller|3D controller/ && /Intel/ && /UHD Graphics|Raptor Lake|Alder Lake|Integrated Graphics/ {print $1; exit}'
}
attach_igpu_to_vm106() {
  local pci short
  pci="$(find_intel_igpu || true)"
  if [[ -z "$pci" ]]; then
    echo "⚠️ Intel iGPU detect edilemedi. VM106 GPU passthrough atlandı."
    return 0
  fi
  short="${pci#0000:}"
  echo "🎬 VM106 Intel iGPU passthrough ekleniyor: $short"
  qm set 106 --hostpci0 "$short,pcie=1" || {
    echo "⚠️ VM106 iGPU passthrough eklenemedi. Sonradan repair script kullan: maintenance/repair/repair-gpu-passthrough.sh"
    return 0
  }
}

AUTO_START=0
create_ubuntu_vm 106 "docker-media" "192.168.50.106/24" "$VM106_RAM_MB" "$VM106_CORES" "$VM106_DISK_SIZE" "yes" "media,tankphotos,privatephotos,ollama"
attach_igpu_to_vm106

if [[ "${AUTO_START_AFTER_GPU:-1}" == "1" ]]; then
  qm start 106 || true
  wait_for_agent 106 80
fi

echo "✅ VM106 hazır. Sonraki aşamada i915 / /dev/dri validation services/common prepare veya GPU repair ile yapılacak."
