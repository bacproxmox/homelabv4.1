#!/usr/bin/env bash
set -Eeuo pipefail

HOMELAB_VERSION="${HOMELAB_VERSION:-2.4.7}"
HOMELAB_ROOT="${HOMELAB_ROOT:-/root/homelabv2.4.7}"
SECRETS_DIR="${SECRETS_DIR:-/root/homelab-secrets}"
LOG_DIR="${LOG_DIR:-/root/homelab-logs}"
STATE_DIR="${STATE_DIR:-/root/homelab-state}"
STACKS_DIR="${STACKS_DIR:-/opt/homelab}"
DOCKER_NETWORK="${DOCKER_NETWORK:-homelab}"

mkdir -p "$SECRETS_DIR" "$LOG_DIR" "$STATE_DIR" "$STACKS_DIR"
chmod 700 "$SECRETS_DIR" "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true

load_env_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  source "$f"
  set +a
}

load_all_env() {
  load_env_file "$SECRETS_DIR/global.env"
  load_env_file "$SECRETS_DIR/users.env"
  load_env_file "$SECRETS_DIR/smtp.env"
  load_env_file "$SECRETS_DIR/cloudflare.env"
  load_env_file "$SECRETS_DIR/google.env"
  load_env_file "$SECRETS_DIR/chia-bootstrap.env"
  load_env_file "$SECRETS_DIR/ollama-models.env"
  load_env_file "$SECRETS_DIR/hardware.env"
  load_env_file "$SECRETS_DIR/truenas-login.env"
  load_env_file "$SECRETS_DIR/truenas.env"
  load_env_file "$SECRETS_DIR/truenas-api.env"
  load_env_file "$SECRETS_DIR/arr-api.env"
  load_env_file "$SECRETS_DIR/jellyfin.env"
  load_env_file "$SECRETS_DIR/immich.env"
}

require_root() { [[ "$(id -u)" -eq 0 ]] || { echo "❌ Root olarak çalıştır."; exit 1; }; }
require_file() { [[ -f "$1" ]] || { echo "❌ Eksik dosya: $1"; exit 1; }; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Eksik komut: $1"; exit 1; }; }
