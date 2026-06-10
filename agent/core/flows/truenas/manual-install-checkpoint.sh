#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$HOMELAB_ROOT/lib/truenas/checkpoint.sh"

require_root
for cmd in qm sshpass ssh-keyscan nmap arp-scan curl ping; do
  command -v "$cmd" >/dev/null 2>&1 || echo "Uyari: komut yok veya sonra gerekebilir: $cmd"
done

wait_for_truenas_manual_install_and_ssh
