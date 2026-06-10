#!/usr/bin/env bash
set -Eeuo pipefail
STATE_DIR="${STATE_DIR:-/root/homelab-state}"
echo "Homelab state dir: $STATE_DIR"
if [[ -f "$STATE_DIR/state.env" ]]; then
  cat "$STATE_DIR/state.env"
else
  echo "Henüz state.env yok."
fi
