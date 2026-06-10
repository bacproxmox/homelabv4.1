#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HOMELAB_ROOT/lib/truenas/checkpoint.sh"

ip="${TRUENAS_HOST:-${TRUENAS_FINAL_IP:-192.168.50.101}}"
refresh_truenas_known_host "$ip"
echo "Known_hosts yenilendi: $ip"
