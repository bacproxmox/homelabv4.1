#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
while [[ ! -f "$ROOT_DIR/bin/homelab" && "$ROOT_DIR" != "/" ]]; do
  ROOT_DIR="$(cd "$ROOT_DIR/.." && pwd)"
done
[[ -f "$ROOT_DIR/bin/homelab" ]] || { echo "Hata: bin/homelab bulunamadi." >&2; exit 127; }

export HOMELAB_ROOT="$ROOT_DIR"
source "$HOMELAB_ROOT/lib/core/env.sh"
source "$HOMELAB_ROOT/lib/core/env-write.sh"
load_all_env

PREF_FILE="$SECRETS_DIR/install-preferences.env"

DEFAULT_BACMASTER_AVATAR_URL="${DEFAULT_BACMASTER_AVATAR_URL:-https://api.dicebear.com/9.x/adventurer/png?seed=Bacmaster}"
DEFAULT_ATLON_AVATAR_URL="${DEFAULT_ATLON_AVATAR_URL:-https://api.dicebear.com/9.x/adventurer/png?seed=Atlon}"
DEFAULT_ELIFEZEL_AVATAR_URL="${DEFAULT_ELIFEZEL_AVATAR_URL:-https://api.dicebear.com/9.x/adventurer/png?seed=Elifezel}"
DEFAULT_TULUMBA_AVATAR_URL="${DEFAULT_TULUMBA_AVATAR_URL:-https://api.dicebear.com/9.x/adventurer/png?seed=Tulumba}"

tty_available() {
  [[ -r /dev/tty && -w /dev/tty ]]
}

tty_print() {
  if tty_available; then
    printf '%b' "$*" >/dev/tty
  else
    printf '%b' "$*"
  fi
}

prompt_value() {
  local var="$1" label="$2" default="$3" value=""
  if tty_available; then
    tty_print "$label [$default]: "
    IFS= read -r value </dev/tty || value=""
  elif [[ -t 0 ]]; then
    printf '%s [%s]: ' "$label" "$default"
    IFS= read -r value || value=""
  else
    value=""
  fi
  [[ -n "$value" ]] || value="$default"
  printf '%s' "$value"
}

prompt_theme() {
  local default="$1" choice=""
  if tty_available; then
    cat >/dev/tty <<'MENU'

Jellyfin tema secimi:
  1) bacsflix            - Homelab yerlesik Bacsflix CSS
  2) finimalism          - tedhinklater/finimalism
  3) elegantfin          - lscambo13/ElegantFin
  4) better-jellyfin-ui  - tromoSM/better-jellyfin-ui
  5) abyss               - AumGupta/abyss-jellyfin
  6) none                - Custom CSS yazma/temayi bos birak
MENU
    tty_print "Secim [$default]: "
    IFS= read -r choice </dev/tty || choice=""
  elif [[ -t 0 ]]; then
    printf 'Jellyfin tema secimi [bacsflix]: '
    IFS= read -r choice || choice=""
  fi

  case "${choice:-$default}" in
    1|bacsflix|Bacsflix) echo "bacsflix" ;;
    2|finimalism|Finimalism) echo "finimalism" ;;
    3|elegantfin|ElegantFin) echo "elegantfin" ;;
    4|better|better-jellyfin-ui|Better) echo "better-jellyfin-ui" ;;
    5|abyss|Abyss) echo "abyss" ;;
    6|none|None|yok|Yok) echo "none" ;;
    *) echo "$default" ;;
  esac
}

if [[ -f "$PREF_FILE" && "${HOMELAB_FORCE_PREFERENCES:-0}" != "1" ]]; then
  echo "Install preferences zaten var: $PREF_FILE"
  echo "Yeniden sormak icin HOMELAB_FORCE_PREFERENCES=1 ile calistir."
  exit 0
fi

echo
echo "Homelab v3.1 install tercihleri kurulum basinda toplanacak."
echo "Bu dosya sonraki servis/theme/avatar adimlari tarafindan okunur: $PREF_FILE"

JELLYFIN_THEME_SELECTED="$(prompt_theme "${JELLYFIN_THEME:-bacsflix}")"
JELLYFIN_BRAND_SELECTED="$(prompt_value JELLYFIN_BRAND "Jellyfin marka adi" "${JELLYFIN_BRAND:-Bacsflix}")"
SEERR_BRAND_SELECTED="$(prompt_value SEERR_BRAND "Seerr/Jellyseerr marka adi" "${SEERR_BRAND:-Bacneyplus}")"
NEXTCLOUD_BRAND_SELECTED="$(prompt_value NEXTCLOUD_BRAND "Nextcloud marka adi" "${NEXTCLOUD_BRAND:-Bacscloud}")"

BACMASTER_AVATAR_SELECTED="$(prompt_value BACMASTER_AVATAR_URL "bacmaster avatar URL" "${BACMASTER_AVATAR_URL:-$DEFAULT_BACMASTER_AVATAR_URL}")"
ATLON_AVATAR_SELECTED="$(prompt_value ATLON_AVATAR_URL "Atlon avatar URL" "${ATLON_AVATAR_URL:-$DEFAULT_ATLON_AVATAR_URL}")"
ELIFEZEL_AVATAR_SELECTED="$(prompt_value ELIFEZEL_AVATAR_URL "Elifezel avatar URL" "${ELIFEZEL_AVATAR_URL:-$DEFAULT_ELIFEZEL_AVATAR_URL}")"
TULUMBA_AVATAR_SELECTED="$(prompt_value TULUMBA_AVATAR_URL "Tulumba avatar URL" "${TULUMBA_AVATAR_URL:-$DEFAULT_TULUMBA_AVATAR_URL}")"

{
  write_env_header
  write_env_line HOMELAB_GUIDED_NONSTOP "1"
  write_env_line HOMELAB_NO_JELLYFIN_WIZARD_PROMPT "1"
  write_env_line JELLYFIN_THEME "$JELLYFIN_THEME_SELECTED"
  write_env_line JELLYFIN_BRAND "$JELLYFIN_BRAND_SELECTED"
  write_env_line SEERR_BRAND "$SEERR_BRAND_SELECTED"
  write_env_line NEXTCLOUD_BRAND "$NEXTCLOUD_BRAND_SELECTED"
  write_env_line SEERR_EMAIL_DOMAIN "${SEERR_EMAIL_DOMAIN:-bacneyplus.local}"
  write_env_line BACMASTER_AVATAR_URL "$BACMASTER_AVATAR_SELECTED"
  write_env_line ATLON_AVATAR_URL "$ATLON_AVATAR_SELECTED"
  write_env_line ELIFEZEL_AVATAR_URL "$ELIFEZEL_AVATAR_SELECTED"
  write_env_line TULUMBA_AVATAR_URL "$TULUMBA_AVATAR_SELECTED"
} > "$PREF_FILE"
chmod 600 "$PREF_FILE"

echo
echo "Install tercihleri yazildi: $PREF_FILE"
echo "Tema: $JELLYFIN_THEME_SELECTED"
echo "Markalar: $JELLYFIN_BRAND_SELECTED / $SEERR_BRAND_SELECTED / $NEXTCLOUD_BRAND_SELECTED"
