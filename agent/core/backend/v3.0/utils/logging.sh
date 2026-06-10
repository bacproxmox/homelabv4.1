#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR="${LOG_DIR:-/root/homelab-logs}"
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"

start_log() {
  local name="${1:-homelab}"
  local logfile="$LOG_DIR/${name}-$(date +%Y%m%d-%H%M%S).log"
  export HOMELAB_CURRENT_LOG="$logfile"
  exec > >(tee -a "$logfile") 2>&1
  echo "📝 Log: $logfile"
}

log_info() { echo "ℹ️  $*"; }
log_ok() { echo "✅ $*"; }
log_warn() { echo "⚠️  $*"; }
log_err() { echo "❌ $*"; }
