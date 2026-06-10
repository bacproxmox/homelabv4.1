#!/usr/bin/env bash
set -Eeuo pipefail

HOMELAB_VERSION="${HOMELAB_VERSION:-3.1.1-r2}"
HOMELAB_ROOT="${HOMELAB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SECRETS_DIR="${SECRETS_DIR:-/root/homelab-secrets}"
LOG_DIR="${LOG_DIR:-/root/homelab-logs}"
STATE_DIR="${STATE_DIR:-/root/homelabv3.1.1-r2-state}"
STATE_FILE="${STATE_FILE:-$STATE_DIR/state.tsv}"
STACKS_DIR="${STACKS_DIR:-/opt/homelab}"
DOCKER_NETWORK="${DOCKER_NETWORK:-homelab}"

mkdir -p "$SECRETS_DIR" "$LOG_DIR" "$STATE_DIR" "$STACKS_DIR"
chmod 700 "$SECRETS_DIR" "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true

load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  source "$file"
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
  load_env_file "$SECRETS_DIR/install-preferences.env"
  load_env_file "$SECRETS_DIR/arr-api.env"
  load_env_file "$SECRETS_DIR/jellyfin.env"
  load_env_file "$SECRETS_DIR/immich.env"
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || {
    echo "Hata: root olarak calistir."
    exit 1
  }
}

require_file() {
  [[ -f "$1" ]] || {
    echo "Hata: eksik dosya: $1"
    exit 1
  }
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Hata: eksik komut: $1"
    exit 1
  }
}
