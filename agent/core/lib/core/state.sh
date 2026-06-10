#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${STATE_DIR:-/root/homelabv3.1.1-r2-state}"
STATE_FILE="${STATE_FILE:-$STATE_DIR/state.tsv}"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR" 2>/dev/null || true
touch "$STATE_FILE"
chmod 600 "$STATE_FILE" 2>/dev/null || true

state_status() {
  local id="$1"
  awk -F'|' -v id="$id" '$1==id {s=$2} END{print s}' "$STATE_FILE"
}

state_mark() {
  local id="$1" status="$2" title="${3:-}"
  local tmp
  tmp="$(mktemp)"
  awk -F'|' -v id="$id" '$1!=id {print}' "$STATE_FILE" > "$tmp" || true
  printf '%s|%s|%s|%s\n' "$id" "$status" "$(date '+%F %T')" "$title" >> "$tmp"
  cat "$tmp" > "$STATE_FILE"
  rm -f "$tmp"
}

state_is_complete() {
  local status
  status="$(state_status "$1")"
  [[ "$status" == "done" || "$status" == "skipped" ]]
}

state_kv_file() {
  local file="$STATE_DIR/state.env"
  touch "$file"
  chmod 600 "$file" 2>/dev/null || true
  printf '%s' "$file"
}

state_set() {
  local key="$1" value="${2:-true}" file tmp
  file="$(state_kv_file)"
  tmp="$(mktemp)"
  grep -v -E "^${key}=" "$file" > "$tmp" || true
  printf '%s=%q\n' "$key" "$value" >> "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

state_get() {
  local key="$1" file
  file="$(state_kv_file)"
  grep -E "^${key}=" "$file" | tail -n1 | cut -d= -f2- | sed 's/^"//;s/"$//'
}
