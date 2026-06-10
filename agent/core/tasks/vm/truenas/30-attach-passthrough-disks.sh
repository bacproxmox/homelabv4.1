#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HOMELAB_ROOT/lib/truenas/vm101.sh"

require_root
require_cmd qm
truenas_validate_disks

qm set "$TRUENAS_VMID" --scsi1 "$TRUENAS_TANK_DISK",serial=TANK20TB
echo "20TB tank passthrough diski takildi: $TRUENAS_TANK_DISK"

if [[ -e "$TRUENAS_PRIVATE_DISK" ]]; then
  qm set "$TRUENAS_VMID" --scsi2 "$TRUENAS_PRIVATE_DISK",serial=PRIVATE4TB
  echo "4TB private passthrough diski takildi: $TRUENAS_PRIVATE_DISK"
elif truenas_private_required; then
  truenas_fail_disk_missing "4TB private disk" "$TRUENAS_PRIVATE_DISK"
else
  echo "⚠️ TRUENAS_PRIVATE_REQUIRED=0; scsi2/private passthrough atlandi."
  qm set "$TRUENAS_VMID" --delete scsi2 >/dev/null 2>&1 || true
fi
