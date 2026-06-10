#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HOMELAB_ROOT/lib/truenas/api.sh"

marker="${SECRETS_DIR:-/root/homelab-secrets}/.fresh-truenas-api-required"
if [[ -f "$marker" ]]; then
  echo "Hata: fresh TrueNAS API key henuz yeniden uretilmemis gorunuyor: $marker"
  echo "Once flows/truenas/postinstall-import-api-network.sh calismali."
  exit 1
fi

truenas_api_readiness
echo "TrueNAS API readiness tamam."
