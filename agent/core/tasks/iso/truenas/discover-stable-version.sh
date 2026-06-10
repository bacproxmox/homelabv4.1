#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HOMELAB_ROOT/lib/truenas/vm101.sh"

require_root
require_cmd curl
require_cmd grep
require_cmd sort

echo "TrueNAS stable surumu araniyor..."
version="$(truenas_discover_latest_version || true)"
[[ -n "$version" ]] || {
  echo "Hata: TrueNAS stable surumu bulunamadi."
  exit 1
}
truenas_write_iso_state "$version"
echo "Bulunan stable surum: $version"
echo "ISO state: $TRUENAS_ISO_STATE"
