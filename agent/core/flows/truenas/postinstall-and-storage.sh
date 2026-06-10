#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$HOMELAB_ROOT/lib/core/runner.sh"

homelab_run "tasks/truenas/postinstall/20-discover-ip.sh"
homelab_run "tasks/truenas/postinstall/30-refresh-known-host.sh"
homelab_run "tasks/truenas/postinstall/40-import-pools-create-api-key-and-network.sh"
homelab_run "flows/truenas/storage-bootstrap.sh"
