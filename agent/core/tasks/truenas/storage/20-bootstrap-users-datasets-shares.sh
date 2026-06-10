#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

legacy="$HOMELAB_ROOT/backend/v3.0/services/truenas/01-truenas-api-bootstrap-storage.sh"
[[ -f "$legacy" ]] || {
  echo "Hata: legacy storage bootstrap script yok: $legacy"
  exit 1
}

bash "$legacy"
