#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
while [[ ! -d "$ROOT_DIR/backend/v3.0" && "$ROOT_DIR" != "/" ]]; do
  ROOT_DIR="$(cd "$ROOT_DIR/.." && pwd)"
done
BACKEND="$ROOT_DIR/backend/v3.0/maintenance/logs/collect-support-bundle.sh"
[[ -f "$BACKEND" ]] || { echo "Hata: backend support bundle bulunamadı: $BACKEND" >&2; exit 127; }
exec bash "$BACKEND" "$@"
