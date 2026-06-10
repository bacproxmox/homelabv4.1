#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HOMELAB_ROOT/lib/truenas/vm101.sh"

truenas_load_iso_state
[[ -s "$TRUENAS_LOCAL_ISO" ]] || {
  echo "Hata: ISO yok veya bos: $TRUENAS_LOCAL_ISO"
  exit 1
}
echo "ISO dogrulandi: $TRUENAS_LOCAL_ISO"
echo "Proxmox ISO ref: $TRUENAS_PVE_ISO"
