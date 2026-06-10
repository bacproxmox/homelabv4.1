#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HOMELAB_ROOT/lib/truenas/api.sh"

load_truenas_api_env
tn_get_json_retry "sharing/nfs" /tmp/truenas-nfs-final-v31.json 10 3
tn_get_json_retry "sharing/smb" /tmp/truenas-smb-final-v31.json 10 3
echo "TrueNAS NFS/SMB final API dogrulamasi tamam."
