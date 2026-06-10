#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "additionals-ai-menu"
while true; do
  clear || true
  cat <<'MENU'
=========================================
 Homelab v2.4.7 - AI / Ollama Models
=========================================
1) List installed models
2) Install selected model
3) Remove model
4) Update installed models
5) Install lightweight pack
6) Install general pack
7) Install developer pack
8) Back
MENU
  read -r -p "Seçim: " choice
  case "$choice" in
    1) bash "$SCRIPT_DIR/list-models.sh" ;;
    2) bash "$SCRIPT_DIR/install-model.sh" ;;
    3) bash "$SCRIPT_DIR/remove-model.sh" ;;
    4) bash "$SCRIPT_DIR/update-models.sh" ;;
    5) bash "$SCRIPT_DIR/model-packs.sh" lightweight ;;
    6) bash "$SCRIPT_DIR/model-packs.sh" general ;;
    7) bash "$SCRIPT_DIR/model-packs.sh" developer ;;
    8) exit 0 ;;
    *) echo "Geçersiz seçim"; sleep 2 ;;
  esac
  read -r -p "Devam için Enter..." _
done
