#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/logging.sh"
start_log "vm-103-docker-network"
source "$SCRIPT_DIR/../lib/vm-cloudinit-common.sh"
VM103_RAM_MB="${VM103_RAM_MB:-2048}"
VM103_BALLOON_MB="${VM103_BALLOON_MB:-1024}"
VM103_ZRAM_MB="${VM103_ZRAM_MB:-1024}"
VM103_CORES="${VM103_CORES:-2}"
export VM103_BALLOON_MB VM103_ZRAM_MB
create_ubuntu_vm 103 "docker-network" "192.168.50.103/24" "$VM103_RAM_MB" "$VM103_CORES" 64G "yes" "none"
