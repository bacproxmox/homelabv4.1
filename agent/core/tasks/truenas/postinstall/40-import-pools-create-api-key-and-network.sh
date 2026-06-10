#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

legacy="$HOMELAB_ROOT/backend/v3.0/services/truenas/00-truenas-postinstall-import-api-network.sh"
[[ -f "$legacy" ]] || {
  echo "Hata: legacy postinstall script yok: $legacy"
  exit 1
}

TRUENAS_SSH_READY_ASSUMED="${TRUENAS_SSH_READY_ASSUMED:-1}" \
TRUENAS_SKIP_BOOT_FIX="${TRUENAS_SKIP_BOOT_FIX:-1}" \
bash "$legacy"
