#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/../lib/core-bridge.sh"
HOMELAB_DESTRUCTIVE_STORAGE_RESET=1 run_core "tasks/proxmox/storage/normalize-local-storage.sh"
