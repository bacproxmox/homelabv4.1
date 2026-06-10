#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HOMELAB_ROOT/lib/truenas/vm101.sh"
source "$HOMELAB_ROOT/lib/proxmox/storage.sh"

ensure_zfs_storage_for_disk "$TRUENAS_VM_STORAGE" "$PVE_NVME_DISK"
