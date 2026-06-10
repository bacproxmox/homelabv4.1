#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/logging.sh"
start_log "vm-102-docker-arr"
source "$SCRIPT_DIR/../lib/vm-cloudinit-common.sh"
VM102_RAM_MB="${VM102_RAM_MB:-8192}"
VM102_BALLOON_MB="${VM102_BALLOON_MB:-4096}"
VM102_ZRAM_MB="${VM102_ZRAM_MB:-2048}"
VM102_CORES="${VM102_CORES:-4}"
export VM102_BALLOON_MB VM102_ZRAM_MB
create_ubuntu_vm 102 "docker-arr" "192.168.50.102/24" "$VM102_RAM_MB" "$VM102_CORES" 256G "yes" "media"
