#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${HOMELABV4_ROOT:-/opt/homelabv4}"
AGENT="${HOMELABV4_AGENT:-$ROOT/agent}"

find_core_root() {
  local candidate
  for candidate in \
    "$ROOT/core" \
    "$AGENT/core" \
    "$ROOT/core/agent/core"
  do
    if [[ -f "$candidate/bin/homelab" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

CORE="$(find_core_root || true)"

run_core() {
  local target="$1"
  shift || true
  if [[ -n "$CORE" && -f "$CORE/bin/homelab" ]]; then
    bash "$CORE/bin/homelab" run "$target" "$@"
    return $?
  fi
  echo "Homelab core runner not found."
  echo "Checked: $ROOT/core, $AGENT/core and $ROOT/core/agent/core"
  echo "Agent is installed, but the v3 core script payload is not available yet."
  exit 3
}

planned_branding_task() {
  local mode="${1:-status}" service="$2" brand="$3"
  echo "Branding pack: $brand / $service"
  echo "Mode: $mode"
  echo "Status: planned"
  echo "This pack is registered in Homelabv4 and awaits service-specific implementation."
}
