#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${HOMELAB_ROOT:-}" ]]; then
  HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

LOG_DIR="${LOG_DIR:-/root/homelab-logs}"
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR" 2>/dev/null || true

start_log() {
  local name="${1:-homelab}"
  local logfile="$LOG_DIR/${name}-$(date +%Y%m%d-%H%M%S).log"
  export HOMELAB_CURRENT_LOG="$logfile"
  exec > >(tee -a "$logfile") 2>&1
  echo "Log: $logfile"
}

log_info() { echo "[INFO] $*"; }
log_ok() { echo "[OK] $*"; }
log_warn() { echo "[WARN] $*"; }
log_err() { echo "[ERR] $*"; }

die() {
  log_err "$*"
  exit 1
}
