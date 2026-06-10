#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${HOMELAB_ROOT:-}" ]]; then
  HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

source "$HOMELAB_ROOT/lib/core/env.sh"

storage_exists() {
  pvesm status 2>/dev/null | awk '{print $1}' | grep -qx "$1"
}

zpool_exists() {
  zpool list "$1" >/dev/null 2>&1
}

root_parent_disks() {
  findmnt -nr -o SOURCE / /boot /boot/efi 2>/dev/null | while read -r src; do
    [[ -n "$src" ]] || continue
    local pk
    pk="$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)"
    [[ -n "$pk" ]] && echo "/dev/$pk"
  done | sort -u
}

is_boot_or_root_disk() {
  local dev="$1"
  root_parent_disks | grep -Fxq "$dev" && return 0
  lsblk -nr -o MOUNTPOINTS "$dev" 2>/dev/null | grep -Eq '(^|[[:space:]])/($|[[:space:]])|/boot|/boot/efi'
}

ensure_zfs_storage_for_disk() {
  local storage="$1" disk="$2"
  require_root
  require_cmd zpool
  require_cmd pvesm
  require_cmd wipefs
  require_cmd sgdisk

  [[ -e "$disk" ]] || {
    echo "Hata: storage diski yok: $disk"
    return 1
  }

  if zpool_exists "$storage"; then
    echo "ZFS pool mevcut: $storage"
  else
    [[ "${HOMELAB_ALLOW_STORAGE_CREATE:-0}" == "1" || "${HOMELAB_DESTRUCTIVE_STORAGE_RESET:-0}" == "1" ]] || {
      echo "Hata: $storage pool yok ve disk hazirlama icin HOMELAB_ALLOW_STORAGE_CREATE=1 gerekli."
      return 1
    }
    if is_boot_or_root_disk "$disk"; then
      echo "Hata: root/boot disk wipe edilmeyecek: $disk"
      return 1
    fi
    echo "ZFS pool olusturuluyor: $storage / $disk"
    wipefs -a "$disk" || true
    sgdisk --zap-all "$disk" || true
    zpool create -f -o ashift=12 "$storage" "$disk"
    zfs set compression=lz4 "$storage"
    zfs set atime=off "$storage"
  fi

  if storage_exists "$storage"; then
    echo "Proxmox storage mevcut: $storage"
  else
    pvesm add zfspool "$storage" -pool "$storage" -content images,rootdir
  fi
}
