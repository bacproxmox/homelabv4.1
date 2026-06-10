#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "immich-storage-verify"
source "$ROOT_DIR/utils/remote.sh"
rssh 106 "set -e; echo 'Immich upload mount:'; df -h /mnt/photos || true; sudo docker inspect hb-immich-server --format '{{json .Mounts}}' | jq . || true"
