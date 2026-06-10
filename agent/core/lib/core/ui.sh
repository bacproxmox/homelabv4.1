#!/usr/bin/env bash
set -Eeuo pipefail

has_whiptail() { command -v whiptail >/dev/null 2>&1; }
has_dialog() { command -v dialog >/dev/null 2>&1; }

ui_msg() {
  local title="$1" text="$2" height="${3:-18}" width="${4:-78}"
  if has_whiptail; then
    whiptail --title "$title" --msgbox "$text" "$height" "$width" || true
  elif has_dialog; then
    dialog --title "$title" --msgbox "$text" "$height" "$width" || true
    clear || true
  else
    echo
    echo "===== $title ====="
    echo "$text"
    echo
    read -r -p "Devam icin Enter..." _ || true
  fi
}

ui_yesno() {
  local title="$1" text="$2" height="${3:-16}" width="${4:-78}"
  if has_whiptail; then
    whiptail --title "$title" --yesno "$text" "$height" "$width"
  elif has_dialog; then
    dialog --title "$title" --yesno "$text" "$height" "$width"
    local rc=$?
    clear || true
    return "$rc"
  else
    local ans
    echo
    echo "===== $title ====="
    echo "$text"
    read -r -p "[y/N]: " ans || true
    [[ "$ans" =~ ^[Yy]$ ]]
  fi
}

ui_menu() {
  local title="$1" text="$2" height="$3" width="$4" menu_height="$5"
  shift 5
  local choice
  if has_whiptail; then
    choice=$(whiptail --title "$title" --menu "$text" "$height" "$width" "$menu_height" "$@" 3>&1 1>&2 2>&3) || return 1
    printf '%s' "$choice"
  elif has_dialog; then
    choice=$(dialog --title "$title" --menu "$text" "$height" "$width" "$menu_height" "$@" 3>&1 1>&2 2>&3) || { clear || true; return 1; }
    clear || true
    printf '%s' "$choice"
  else
    local items=("$@") i ans
    echo
    echo "===== $title ====="
    echo "$text"
    i=0
    while (( i < ${#items[@]} )); do
      printf '  %s) %s\n' "${items[$i]}" "${items[$((i+1))]}"
      i=$((i+2))
    done
    read -r -p "Secim: " ans || return 1
    printf '%s' "$ans"
  fi
}
