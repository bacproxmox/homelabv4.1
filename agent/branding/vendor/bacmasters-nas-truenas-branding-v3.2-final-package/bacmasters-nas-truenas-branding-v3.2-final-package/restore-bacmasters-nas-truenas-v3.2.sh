#!/usr/bin/env bash
set -Eeuo pipefail

# Disables the Bacmaster's NAS WebUI injection by removing the index.html loader block.
# Assets/backups may remain on TrueNAS, but they are not loaded after restore.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
V7="$SCRIPT_DIR/scripts/apply-truenas-bacmasters-ui-branding-v7.sh"

if [[ ! -f "$V7" ]]; then
  echo "ERROR: Missing bundled restore-capable script: $V7"
  exit 10
fi
chmod +x "$V7"

bash "$V7" restore

echo

echo "✅ Bacmaster's NAS branding injection disabled."
echo "Open a new private window or hard refresh TrueNAS."
