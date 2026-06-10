#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HOMELAB_ROOT/lib/truenas/vm101.sh"

require_root
require_cmd qm
truenas_load_iso_state
[[ -s "$TRUENAS_LOCAL_ISO" ]] || {
  echo "Hata: once ISO indirilmeli: $TRUENAS_LOCAL_ISO"
  exit 1
}

qm set "$TRUENAS_VMID" --ide2 "$TRUENAS_PVE_ISO",media=cdrom
qm set "$TRUENAS_VMID" --boot order=ide2
echo "Installer ISO takildi: $TRUENAS_PVE_ISO"
