#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
while [[ ! -f "$ROOT_DIR/bin/homelab" && "$ROOT_DIR" != "/" ]]; do
  ROOT_DIR="$(cd "$ROOT_DIR/.." && pwd)"
done
[[ -f "$ROOT_DIR/bin/homelab" ]] || { echo "Hata: bin/homelab bulunamadi." >&2; exit 127; }

export HOMELAB_ROOT="$ROOT_DIR"
export HOMELAB_NO_JELLYFIN_WIZARD_PROMPT="${HOMELAB_NO_JELLYFIN_WIZARD_PROMPT:-1}"
export HOMELAB_NO_JELLYFIN_WIZARD_GATE="${HOMELAB_NO_JELLYFIN_WIZARD_GATE:-1}"

source "$HOMELAB_ROOT/lib/core/runner.sh"

failures=()
warnings=()
run_critical() {
  local title="$1" target="$2" rc
  echo
  echo "==> $title"
  set +e
  homelab_run "$target"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    return 0
  fi
  failures+=("$target:$rc")
  echo "Uyari: $title hata verdi ($rc); sonraki post-config adimlari yine de denenmeye devam edecek."
  return 0
}

run_optional_post_config() {
  local title="$1" target="$2" rc
  echo
  echo "==> $title"
  set +e
  homelab_run "$target"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    return 0
  fi
  warnings+=("$target:$rc")
  echo "Uyari: $title tamamlanamadi ($rc); bu adim sonradan tekrar calistirilabilir."
  return 0
}

run_critical "Core config (v3.0 backend, non-interactive gate)" "backend/v3.0/config/00-run-all-core-config.sh"
run_optional_post_config "Jellyfin tema secimi uygula" "tasks/config/jellyfin/apply-theme.sh"
run_optional_post_config "Bacsflix/Bacneyplus/Bacscloud profil ve avatar uygula" "tasks/profiles/apply-service-profiles.sh"

if (( ${#failures[@]} > 0 )); then
  echo
  echo "Core config/branding flow bazi hatalarla tamamlandi:"
  printf '  - %s\n' "${failures[@]}"
  exit 1
fi

if (( ${#warnings[@]} > 0 )); then
  echo
  echo "Post-config/profil uyarilari:"
  printf '  - %s\n' "${warnings[@]}"
  echo "Bu uyarilar Full Install sonucunu basarisiz saydirmaz; ilgili task'lar panelden tekrar calistirilabilir."
fi

echo
echo "Core config + branding/profil flow tamamlandi."
