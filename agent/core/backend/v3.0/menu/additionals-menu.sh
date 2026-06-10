#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "additionals-menu"
while true; do
  clear || true
  cat <<'MENU'
=========================================
 Homelab v2.4.7 - Additionals Menu
=========================================
1) AI / Ollama model management
2) Profile pictures / avatars
3) Themes / branding
4) Auth / SSO experiments
5) Network additionals
6) Back
MENU
  read -r -p "Seçim: " choice
  case "$choice" in
    1) bash "$ROOT_DIR/additionals/ai/ai-menu.sh" ;;
    2) bash "$ROOT_DIR/additionals/profiles/profile-menu.sh" ;;
    3) bash "$ROOT_DIR/additionals/themes/themes-menu.sh" ;;
    4) bash "$ROOT_DIR/additionals/auth/auth-menu.sh" ;;
    5) bash "$ROOT_DIR/additionals/network/network-menu.sh" ;;
    6) exit 0 ;;
    *) echo "Geçersiz seçim"; sleep 2 ;;
  esac
  read -r -p "Devam için Enter..." _
done
