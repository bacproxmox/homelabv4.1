#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/logging.sh"
start_log "vm-104-nextcloud"
source "$SCRIPT_DIR/../lib/vm-cloudinit-common.sh"
VM104_RAM_MB="${VM104_RAM_MB:-8192}"
VM104_BALLOON_MB="${VM104_BALLOON_MB:-4096}"
VM104_ZRAM_MB="${VM104_ZRAM_MB:-2048}"
VM104_CORES="${VM104_CORES:-4}"
export VM104_BALLOON_MB VM104_ZRAM_MB
create_ubuntu_vm 104 "nextcloud" "192.168.50.104/24" "$VM104_RAM_MB" "$VM104_CORES" 128G "yes" "privatedocuments"
