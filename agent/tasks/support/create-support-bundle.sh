#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${HOMELABV4_ROOT:-/opt/homelabv4}"
OUT="/root/homelabv4-support-$(date +%Y%m%d-%H%M%S).tar.gz"
TMP="$(mktemp -d /tmp/homelabv4-support.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP"
cp -a "$ROOT/state" "$TMP/state" 2>/dev/null || true
cp -a "$ROOT/logs" "$TMP/logs" 2>/dev/null || true
mkdir -p "$TMP/qemu-server" "$TMP/root-homelab-logs"
cp -a /etc/pve/qemu-server/*.conf "$TMP/qemu-server/" 2>/dev/null || true
if [[ -d /root/homelab-logs ]]; then
  for log in /root/homelab-logs/*.log; do
    [[ -f "$log" ]] || continue
    sed -E \
      -e 's/((PASS|PASSWORD|TOKEN|SECRET|MNEMONIC|API_KEY|CLIENT_SECRET|APP_PASS|KEY)[A-Z0-9_]*=).*/\1***REDACTED***/Ig' \
      -e 's/(sshpass[[:space:]]+-p[[:space:]]+)[^[:space:]]+/\1***REDACTED***/Ig' \
      "$log" > "$TMP/root-homelab-logs/$(basename "$log")" 2>/dev/null || true
  done
fi
lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,TRAN,FSTYPE,MOUNTPOINTS > "$TMP/lsblk.txt" 2>&1 || true
pvesm status > "$TMP/pvesm-status.txt" 2>&1 || true
find /dev/disk/by-id -maxdepth 1 -type l -printf '%f -> %l\n' > "$TMP/disk-by-id.txt" 2>&1 || true
dmesg -T | grep -Ei 'error|failed|reset|I/O|nvme|ata|vfio|nvidia' | tail -300 > "$TMP/dmesg-interesting.txt" 2>&1 || true
tar -C "$TMP" -czf "$OUT" .
echo "Support bundle: $OUT"
