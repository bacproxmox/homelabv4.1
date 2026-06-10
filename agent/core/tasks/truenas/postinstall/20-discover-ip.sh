#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HOMELAB_ROOT/lib/truenas/checkpoint.sh"

require_root
ip="${TRUENAS_FINAL_IP:-192.168.50.101}"
if ping -c1 -W1 "$ip" >/dev/null 2>&1; then
  echo "TrueNAS final IP ping veriyor: $ip"
  write_truenas_host_to_login_env "$ip"
  exit 0
fi

found="$(find_truenas_ip_by_mac || true)"
[[ -n "$found" ]] || {
  echo "Hata: TrueNAS IP bulunamadi."
  exit 1
}
echo "TrueNAS IP bulundu: $found"
write_truenas_host_to_login_env "$found"
