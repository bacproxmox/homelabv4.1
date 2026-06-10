#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/utils/logging.sh"
start_log "vm-107-chia-farmer"
source "$REPO_ROOT/lib/vm-cloudinit-common.sh"

CHIA_VM_STORAGE="${CHIA_VM_STORAGE:-nvme-vm-two}"
if ! pvesm status 2>/dev/null | awk '{print $1}' | grep -qx "$CHIA_VM_STORAGE"; then
  echo "❌ VM107 için storage bulunamadı: $CHIA_VM_STORAGE"
  echo "v2.4.6 standardı: MLD M500 NVMe üzerinde nvme-vm-two oluşturulmalı."
  echo "Önce Install Menu -> 12 Normalize Proxmox local storage çalıştır."
  exit 1
fi
VM_STORAGE="$CHIA_VM_STORAGE"
export VM_STORAGE

calc_chia_disk_size() {
  local storage="$1"
  local total_kib total_gib reserved reserve disk_gib
  total_kib="$(pvesm status 2>/dev/null | awk -v s="$storage" '$1==s {print $4; exit}')"
  [[ -n "$total_kib" && "$total_kib" =~ ^[0-9]+$ ]] || { echo "${CHIA_VM_DISK_SIZE:-512G}"; return 0; }

  total_gib=$(( total_kib / 1024 / 1024 ))
  reserved="${VM106_RESERVED_GB:-512}"
  reserve="${NVME_VM_TWO_FREE_RESERVE_GB:-64}"
  disk_gib=$(( total_gib - reserved - reserve ))

  if (( disk_gib < 128 )); then
    echo "ERR:${total_gib}:${reserved}:${reserve}"
    return 0
  fi

  echo "${disk_gib}G"
}

CHIA_VM_DISK_SIZE="${CHIA_VM_DISK_SIZE:-$(calc_chia_disk_size "$CHIA_VM_STORAGE")}"
if [[ "$CHIA_VM_DISK_SIZE" == ERR:* ]]; then
  IFS=':' read -r _ total reserved reserve <<<"$CHIA_VM_DISK_SIZE"
  echo "❌ nvme-vm-two kapasitesi VM106+VM107 bölüşümü için yetersiz görünüyor."
  echo "   total=${total}GiB, VM106_reserved=${reserved}GiB, free_reserve=${reserve}GiB"
  echo "   Daha büyük MLD M500/NVMe gerekir veya CHIA_VM_DISK_SIZE manuel override edilmeli."
  exit 1
fi
echo "💽 VM107 disk boyutu: $CHIA_VM_DISK_SIZE (storage=$CHIA_VM_STORAGE, VM106_RESERVED_GB=${VM106_RESERVED_GB:-512}, reserve=${NVME_VM_TWO_FREE_RESERVE_GB:-64}G)"

find_nvidia_gpu() {
  lspci -Dnn | awk '/VGA compatible controller|3D controller/ && /NVIDIA/ {print $1; exit}'
}
find_nvidia_audio_for_gpu() {
  local gpu="$1" base audio
  base="${gpu%.*}"
  audio="${base}.1"
  if lspci -Dnn | awk '{print $1}' | grep -Fxq "$audio" && lspci -Dnn -s "$audio" | grep -qi 'NVIDIA.*Audio'; then
    echo "$audio"
  fi
}
find_jmicron_sata_controllers() {
  # 2x JMicron/JMB/JMS58x M.2/NVMe-to-SATA adapters carrying Chia plot disks.
  # Keep this narrow: never passthrough Intel onboard SATA or TrueNAS raw disks here.
  lspci -Dnn | awk 'BEGIN{IGNORECASE=1} /SATA controller|AHCI/ && /JMicron|JMB|JMS|JMB58|JMS58|JMB585|JMB582/ {print $1}' | sort -u
}
attach_jmicron_to_vm107() {
  local idx=2 count=0 pci short
  echo "💽 VM107 JMicron/JMB/JMS58x SATA controller passthrough aranıyor..."
  while read -r pci; do
    [[ -n "$pci" ]] || continue
    short="${pci#0000:}"
    echo "💽 VM107 Chia plot SATA controller passthrough ekleniyor: hostpci${idx}=$short"
    qm set 107 --hostpci${idx} "$short,pcie=1" || echo "⚠️ hostpci${idx} eklenemedi: $short"
    idx=$((idx+1)); count=$((count+1))
  done < <(find_jmicron_sata_controllers)
  if [[ "$count" -eq 0 ]]; then
    echo "⚠️ JMicron/JMB/JMS58x SATA controller bulunamadı. VM107 plot diskleri eksik kalabilir."
  else
    echo "✅ JMicron controller sayısı: $count"
  fi
}
attach_nvidia_to_vm107() {
  local gpu audio short audio_short
  gpu="$(find_nvidia_gpu || true)"
  if [[ -z "$gpu" ]]; then
    echo "⚠️ NVIDIA GPU detect edilemedi. VM107 GPU passthrough atlandı."
    return 0
  fi
  short="${gpu#0000:}"
  echo "🌱 VM107 NVIDIA GPU passthrough ekleniyor: $short"
  qm set 107 --hostpci0 "$short,pcie=1" || {
    echo "⚠️ VM107 NVIDIA GPU passthrough eklenemedi. Sonradan repair script kullan: maintenance/repair/repair-gpu-passthrough.sh"
    return 0
  }
  audio="$(find_nvidia_audio_for_gpu "$gpu" || true)"
  if [[ -n "$audio" ]]; then
    audio_short="${audio#0000:}"
    echo "🔊 VM107 NVIDIA audio function passthrough deneniyor: $audio_short"
    qm set 107 --hostpci1 "$audio_short,pcie=1" || echo "⚠️ NVIDIA audio eklenemedi; CUDA için çoğu senaryoda kritik değil."
  fi
}

AUTO_START=0
create_ubuntu_vm 107 "chia-farmer" "192.168.50.107/24" "${VM107_RAM_MB:-8192}" "${VM107_CORES:-4}" "$CHIA_VM_DISK_SIZE" "yes" "none"
attach_nvidia_to_vm107
attach_jmicron_to_vm107

if [[ "${AUTO_START_AFTER_GPU:-1}" == "1" ]]; then
  qm start 107 || true
  wait_for_agent 107 80
fi

echo "✅ VM107 hazır. NVIDIA + JMicron/plot disk validation Phase 4 veya maintenance repair ile yapılacak."
