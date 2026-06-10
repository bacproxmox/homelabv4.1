#!/usr/bin/env bash
set -Eeuo pipefail
STATE_DIR="${STATE_DIR:-/root/homelab-state}"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

state_set() {
  local key="$1"
  local value="${2:-true}"
  local f="$STATE_DIR/state.env"
  touch "$f"
  chmod 600 "$f"
  if grep -q "^${key}=" "$f"; then
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$f"
  else
    echo "${key}=\"${value}\"" >> "$f"
  fi
}

state_get() {
  local key="$1"
  local f="$STATE_DIR/state.env"
  [[ -f "$f" ]] || return 1
  grep -E "^${key}=" "$f" | tail -n1 | cut -d= -f2- | sed 's/^"//;s/"$//'
}
