#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HOMELAB_ROOT/lib/truenas/vm101.sh"

require_root
for cmd in qm pvesm; do require_cmd "$cmd"; done
truenas_validate_disks

if qm status "$TRUENAS_VMID" >/dev/null 2>&1; then
  if qm status "$TRUENAS_VMID" | grep -q running; then
    echo "Hata: VM $TRUENAS_VMID calisiyor. Donanim guncellemek icin once kapat."
    exit 1
  fi
  echo "VM $TRUENAS_VMID zaten var; donanim ayarlari sonraki tasklarda dogrulanacak."
else
  echo "TrueNAS VM olusturuluyor: $TRUENAS_VMID / $TRUENAS_VMNAME"
  qm create "$TRUENAS_VMID" \
    --name "$TRUENAS_VMNAME" \
    --memory "$TRUENAS_VM_RAM" \
    --cores 4 \
    --cpu host \
    --machine q35 \
    --bios ovmf \
    --scsihw virtio-scsi-single \
    --net0 "virtio=${TRUENAS_FIXED_MAC},bridge=vmbr0" \
    --onboot 1 \
    --balloon 0 \
    --vga vmware
fi

qm set "$TRUENAS_VMID" --net0 "virtio=${TRUENAS_FIXED_MAC},bridge=vmbr0"
qm set "$TRUENAS_VMID" --efidisk0 "$TRUENAS_VM_STORAGE":1,format=raw,efitype=4m
qm set "$TRUENAS_VMID" --scsi0 "$TRUENAS_VM_STORAGE":"$TRUENAS_OS_DISK",discard=on,ssd=1,iothread=1
echo "VM shell/OS disk hazir."
