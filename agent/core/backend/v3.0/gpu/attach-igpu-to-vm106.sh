#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/utils/logging.sh"
start_log "attach-igpu-vm106"
source "$SCRIPT_DIR/lib/vm-cloudinit-common.sh"
require_root
VMID=106
GPU="$(find_pci_by_regex 'VGA compatible controller.*Intel|Display controller.*Intel|Raptor Lake.*Graphics|UHD Graphics')"
[[ -n "$GPU" ]] || { echo "❌ Intel iGPU bulunamadı."; lspci -nn | grep -Ei 'vga|display|3d'; exit 1; }
GPU_SHORT="$(pci_short "$GPU")"
echo "🔌 VM106 iGPU passthrough: $GPU_SHORT"
qm set "$VMID" -hostpci0 "$GPU_SHORT,pcie=1,rombar=0,x-vga=0"
echo "✅ Eklendi. VM açılmazsa: qm set 106 --delete hostpci0"
