#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../utils/logging.sh"
source "$SCRIPT_DIR/../../../utils/remote.sh"
start_log "apply-dynamic-ram-profile"

set_vm_resources() {
  local vmid="$1" mem="$2" cores="$3" balloon="$4"
  if ! qm status "$vmid" >/dev/null 2>&1; then
    echo "VM $vmid not found, skipping resource update."
    return 0
  fi
  echo "Setting VM $vmid resources: memory=${mem}MB balloon=${balloon}MB cores=${cores}"
  qm set "$vmid" --memory "$mem" --cores "$cores" --balloon "$balloon"
}

install_zram() {
  local vmid="$1" zram_mb="$2"
  [[ "$zram_mb" != "0" ]] || return 0
  if ! qm status "$vmid" >/dev/null 2>&1; then
    echo "VM $vmid not found, skipping zram."
    return 0
  fi
  if ! rssh "$vmid" 'echo ok' >/dev/null 2>&1; then
    echo "VM $vmid SSH not reachable, skipping live zram install. Recreate/cloud-init or rerun repair later."
    return 0
  fi

  echo "Installing zram safety swap inside VM $vmid: ${zram_mb}MB"
  rssh "$vmid" "sudo ZRAM_MB='$zram_mb' bash -s" <<'REMOTE'
set -Eeuo pipefail
printf 'vm.swappiness=10\n' >/etc/sysctl.d/90-homelab-memory.conf
sysctl --system >/dev/null || true
cat >/etc/systemd/system/homelab-zram-swap.service <<UNIT
[Unit]
Description=Homelab zram swap
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -lc 'if swapon --show=NAME --noheadings | grep -q "^/dev/zram"; then exit 0; fi; modprobe zram || true; dev="\$(zramctl -f --algorithm zstd --size ${ZRAM_MB}M 2>/dev/null || zramctl -f --algorithm lz4 --size ${ZRAM_MB}M 2>/dev/null || zramctl -f --size ${ZRAM_MB}M)"; mkswap "\$dev"; swapon -p 100 "\$dev"'
ExecStop=/bin/bash -lc 'for dev in \$(swapon --show=NAME --noheadings | grep "^/dev/zram" || true); do swapoff "\$dev" || true; zramctl -r "\$dev" || true; done'

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now homelab-zram-swap.service || true
swapon --show=NAME,SIZE,PRIO | grep -E 'NAME|/dev/zram' || true
REMOTE
}

echo "Applying Homelabv4.1 dynamic RAM profile."
set_vm_resources 101 16384 4 0
set_vm_resources 102 8192 4 4096
set_vm_resources 103 2048 2 1024
set_vm_resources 104 8192 4 4096
set_vm_resources 105 2048 2 1024
set_vm_resources 106 65536 8 32768
set_vm_resources 107 8192 4 0
set_vm_resources 110 4096 2 2048

install_zram 102 2048
install_zram 103 1024
install_zram 104 2048
install_zram 105 1024
install_zram 106 8192
install_zram 110 1024

echo
echo "Dynamic RAM profile applied."
echo "Note: Proxmox max memory changes may require a VM reboot if the guest does not support live memory hotplug."
