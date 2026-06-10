#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
while [[ ! -f "$ROOT_DIR/bin/homelab" && "$ROOT_DIR" != "/" ]]; do
  ROOT_DIR="$(cd "$ROOT_DIR/.." && pwd)"
done
[[ -f "$ROOT_DIR/bin/homelab" ]] || { echo "Hata: bin/homelab bulunamadi." >&2; exit 127; }
exec bash "$ROOT_DIR/bin/homelab" run "backend/v3.0/services/jellyfin/01-jellyfin-service-install.sh" "$@"

