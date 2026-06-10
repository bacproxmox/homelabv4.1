#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${HOMELAB_ROOT:-}" ]]; then
  HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

resolve_homelab_target() {
  local target="$1"
  local candidate=""

  if [[ "$target" = /* ]]; then
    [[ -f "$target" ]] && { printf '%s\n' "$target"; return 0; }
    [[ -f "${target}.sh" ]] && { printf '%s\n' "${target}.sh"; return 0; }
  fi

  for candidate in \
    "$HOMELAB_ROOT/$target" \
    "$HOMELAB_ROOT/${target}.sh" \
    "$HOMELAB_ROOT/tasks/$target" \
    "$HOMELAB_ROOT/tasks/${target}.sh" \
    "$HOMELAB_ROOT/flows/$target" \
    "$HOMELAB_ROOT/flows/${target}.sh"
  do
    [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done

  return 1
}

homelab_run() {
  local target="$1"
  shift || true
  local script
  script="$(resolve_homelab_target "$target")" || {
    echo "Hata: hedef bulunamadi: $target" >&2
    return 127
  }
  bash "$script" "$@"
}

homelab_wrapper_run() {
  local target="$1"
  shift || true
  if [[ -x "$HOMELAB_ROOT/bin/homelab" ]]; then
    "$HOMELAB_ROOT/bin/homelab" run "$target" "$@"
  else
    bash "$HOMELAB_ROOT/bin/homelab" run "$target" "$@"
  fi
}

run_logged() {
  local title="$1"
  shift
  echo
  echo "==> $title"
  "$@"
}

run_optional() {
  local title="$1"
  shift
  if run_logged "$title" "$@"; then
    return 0
  fi
  local rc=$?
  echo "Uyari: opsiyonel adim hata verdi ($rc): $title"
  return 0
}
