#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "repair-gpu-passthrough"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
source "$ROOT_DIR/lib/vm-cloudinit-common.sh"

find_intel_igpu() {
  lspci -Dnn | awk '/VGA compatible controller|Display controller|3D controller/ && /Intel/ && /UHD Graphics|Raptor Lake|Alder Lake|Integrated Graphics/ {print $1; exit}'
}

find_nvidia_gpu() {
  lspci -Dnn | awk '/VGA compatible controller|3D controller/ && /NVIDIA/ {print $1; exit}'
}

find_nvidia_audio() {
  local gpu="$1" base audio
  base="${gpu%.*}"
  audio="${base}.1"
  lspci -Dnn -s "$audio" | grep -qi 'NVIDIA.*Audio' && echo "$audio" || true
}

find_jmicron_sata() {
  lspci -Dnn | awk 'BEGIN{IGNORECASE=1} /SATA controller|AHCI/ && /JMicron|JMB|JMS|JMB58|JMS58|JMB585|JMB582/ {print $1}' | sort -u
}

stop_if_running() {
  local vm="$1"
  if qm status "$vm" 2>/dev/null | grep -q running; then
    qm shutdown "$vm" --timeout 60 || qm stop "$vm" || true
  fi
}

start_and_wait() {
  local vm="$1"
  qm start "$vm" || true
  wait_for_agent "$vm" 80 || true
  wait_ssh "$vm" || true
}

attach_vm106() {
  local pci short
  pci="$(find_intel_igpu || true)"
  [[ -n "$pci" ]] || { echo "Intel iGPU not found."; return 1; }
  short="${pci#0000:}"
  echo "VM106 iGPU attach: $short"
  stop_if_running 106
  qm set 106 --hostpci0 "$short,pcie=1"
  start_and_wait 106
}

fix_vm106_driver() {
  echo "Checking VM106 i915 and VAAPI packages."
  wait_ssh 106
  rssh 106 'sudo bash -lc '"'"'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y vainfo intel-media-va-driver-non-free intel-gpu-tools
if modinfo i915 >/dev/null 2>&1; then
  echo "i915 module already available on the active kernel; skipping guest kernel upgrade."
else
  echo "i915 module missing on active kernel; installing linux-modules-extra for current kernel only."
  apt-get install -y "linux-modules-extra-$(uname -r)" || true
fi
if ! modinfo i915 >/dev/null 2>&1 && [[ "${HOMELAB_ALLOW_GUEST_KERNEL_UPGRADE:-0}" == "1" ]]; then
  echo "HOMELAB_ALLOW_GUEST_KERNEL_UPGRADE=1 set; installing linux-generic/linux-firmware fallback."
  apt-get install -y linux-generic linux-firmware
fi
'"'"''

  if ! rssh 106 'modinfo i915 >/dev/null 2>&1'; then
    echo "WARNING: i915 is still missing on the active VM106 kernel."
    echo "Guest kernel upgrade was not automatic. Re-run GPU repair with HOMELAB_ALLOW_GUEST_KERNEL_UPGRADE=1 if needed."
  elif rssh 106 'test -e /dev/dri/renderD128'; then
    echo "VM106 /dev/dri is ready; reboot not needed."
  fi

  rssh 106 'sudo modprobe i915 || true; ls -lah /dev/dri || true; sudo lspci -nnk | grep -A3 -Ei "Raptor Lake-S UHD|UHD Graphics|i915" || true; vainfo --display drm --device /dev/dri/renderD128 || true'
}

attach_vm107_hardware() {
  local gpu audio short audio_short idx=2 pci count=0
  gpu="$(find_nvidia_gpu || true)"
  if [[ -n "$gpu" ]]; then
    short="${gpu#0000:}"
    echo "VM107 NVIDIA attach: $short"
    qm set 107 --hostpci0 "$short,pcie=1" || true
    audio="$(find_nvidia_audio "$gpu" || true)"
    if [[ -n "$audio" ]]; then
      audio_short="${audio#0000:}"
      qm set 107 --hostpci1 "$audio_short,pcie=1" || echo "NVIDIA audio attach skipped or failed."
    fi
  else
    echo "NVIDIA GPU not found."
  fi

  while read -r pci; do
    [[ -n "$pci" ]] || continue
    short="${pci#0000:}"
    echo "VM107 JMicron/JMB/JMS SATA attach hostpci${idx}: $short"
    qm set 107 --hostpci${idx} "$short,pcie=1" || true
    idx=$((idx + 1))
    count=$((count + 1))
  done < <(find_jmicron_sata)

  [[ "$count" -gt 0 ]] && echo "VM107 JMicron controller count: $count" || echo "JMicron/JMB/JMS SATA controller not found."
}

fix_vm107_driver_and_disks() {
  echo "Checking VM107 NVIDIA/JMicron/Chia disks."
  wait_ssh 107
  rssh 107 'lspci -nn | grep -Ei "nvidia|jmicron|jmb|jms|sata|ahci|vga|3d" || true; nvidia-smi || true; find /dev/disk/by-id -maxdepth 1 -type l | grep -Ei "TOSHIBA_HDWG|HDWG180|HDWG480" | sort || true; lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,TRAN,MOUNTPOINTS || true'
  bash "$ROOT_DIR/maintenance/repair/repair-chia-plot-disks.sh" || true
}

echo "Starting GPU + Chia hardware passthrough repair."
attach_vm106 || true
fix_vm106_driver || true
stop_if_running 107
attach_vm107_hardware || true
start_and_wait 107
fix_vm107_driver_and_disks || true

echo "GPU/Chia passthrough repair completed."
