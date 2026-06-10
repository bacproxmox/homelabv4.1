#!/usr/bin/env bash
set -Eeuo pipefail
echo "===== Homelabv4 hardware preflight ====="
lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,TRAN,FSTYPE,MOUNTPOINTS || true
echo
nvme list 2>/dev/null || true
echo
lspci -Dnn 2>/dev/null | grep -Ei 'vga|3d|display|nvidia|intel|jmicron|jmb|jms|sata|ahci' || true
