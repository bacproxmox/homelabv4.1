#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HOMELAB_ROOT/lib/truenas/vm101.sh"

require_root
require_cmd wget
require_cmd curl

truenas_load_iso_state
mkdir -p "$TRUENAS_ISO_DIR"

echo "TrueNAS ISO: $TRUENAS_ISO_URL"
echo "Hedef: $TRUENAS_LOCAL_ISO"
if [[ -s "$TRUENAS_LOCAL_ISO" ]]; then
  echo "ISO zaten mevcut."
else
  wget -O "$TRUENAS_LOCAL_ISO" "$TRUENAS_ISO_URL"
fi
