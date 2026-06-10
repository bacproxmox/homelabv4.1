#!/usr/bin/env bash
set -Eeuo pipefail

STORAGE_CFG="/etc/pve/storage.cfg"
BACKUP_DIR="/root/homelab-backups/storage"
TARGET_MAIN_STORAGE="nvme-vm"
TARGET_MAIN_POOL="nvme-vm"
TARGET_MEDIA_STORAGE="nvme-vm-two"
TARGET_MEDIA_POOL="nvme-vm-two"
KNOWN_MAIN_SERIAL="2J4520139863"
KNOWN_MLD_SERIAL="7CBC0759131100037331"
DESTRUCTIVE_RESET="${HOMELAB_DESTRUCTIVE_STORAGE_RESET:-0}"
mkdir -p "$BACKUP_DIR"

echo
echo "🧩 Proxmox local + Homelab NVMe storage normalize ediliyor..."
echo "💽 Homelab v2.4.7 storage kontrolü"
echo "  $TARGET_MAIN_STORAGE     : 2TB XPG SPECTRIX S40G NVMe"
echo "  $TARGET_MEDIA_STORAGE: MLD/MDL/M500 NVMe veya serial $KNOWN_MLD_SERIAL"

if [[ "$DESTRUCTIVE_RESET" == "1" ]]; then
  echo "⚠️ DESTRUCTIVE MODE: nvme-vm ve nvme-vm-two onay sormadan wipe/recreate edilecek."
else
  echo "ℹ️ SAFE MODE: mevcut pool/storage register edilir; disk wipe yapılmaz."
  echo "   Guided fresh pipeline destructive mod ile çağırır."
fi

if [[ ! -f "$STORAGE_CFG" ]]; then
  echo "❌ $STORAGE_CFG bulunamadı. Bu script Proxmox host üzerinde çalışmalı."
  exit 1
fi

cp "$STORAGE_CFG" "$BACKUP_DIR/storage.cfg.backup.before-v246-r2.$(date +%F-%H%M%S)" || true

# Normalize legacy/disabled local block.
awk '
BEGIN { skip=0 }
$0=="dir: local" { skip=1; next }
skip && NF==0 { skip=0; next }
!skip { print }
' "$STORAGE_CFG" > /tmp/storage.cfg.new
cat /tmp/storage.cfg.new > "$STORAGE_CFG"

sed -i \
  -e 's/^btrfs: local-system$/btrfs: local/' \
  -e 's/^btrfs: local-btrfs$/btrfs: local/' \
  "$STORAGE_CFG"

storage_exists() { pvesm status 2>/dev/null | awk '{print $1}' | grep -qx "$1"; }
zpool_exists() { zpool list -H -o name 2>/dev/null | grep -qx "$1"; }
importable_zpool_exists() { zpool import 2>/dev/null | awk -v p="$1" '$1=="pool:" && $2==p {found=1} END{exit found?0:1}'; }

root_parent_disks() {
  local src pk
  for mp in / /boot /boot/efi; do
    src="$(findmnt -no SOURCE "$mp" 2>/dev/null || true)"
    [[ -n "$src" ]] || continue
    pk="$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)"
    [[ -n "$pk" ]] && echo "/dev/$pk"
  done | sort -u
}

is_boot_or_root_disk() {
  local dev="$1"
  root_parent_disks | grep -Fxq "$dev" && return 0
  lsblk -nr -o MOUNTPOINTS "$dev" 2>/dev/null | grep -Eq '(^|[[:space:]])/($|[[:space:]])|/boot|/boot/efi'
}

is_sata_or_hdd() {
  local dev="$1"
  [[ "$(basename "$dev")" != nvme*n1 ]]
}

dev_info() {
  local dev="$1" name model serial size bytes byid
  name="$(basename "$dev")"
  model="$(cat "/sys/block/$name/device/model" 2>/dev/null | tr -s ' ' ' ' | sed 's/^ *//;s/ *$//' || true)"
  serial="$(cat "/sys/block/$name/device/serial" 2>/dev/null | tr -s ' ' ' ' | sed 's/^ *//;s/ *$//' || true)"
  size="$(lsblk -dn -o SIZE "$dev" 2>/dev/null | tr -s ' ' ' ' | sed 's/^ *//;s/ *$//' || true)"
  bytes="$(blockdev --getsize64 "$dev" 2>/dev/null || echo 0)"
  byid="$(find /dev/disk/by-id -maxdepth 1 -type l -name 'nvme-*' 2>/dev/null | while read -r l; do [[ "$(readlink -f "$l")" == "$dev" ]] && basename "$l"; done | paste -sd ' ' -)"
  printf '%s|%s|%s|%s|%s' "${model:-unknown}" "${serial:-unknown}" "${size:-unknown}" "${bytes:-0}" "${byid:-}"
}

looks_like_main_nvme() {
  local text="$1" bytes="${2:-0}"
  if grep -Eiq "XPG.*SPECTRIX.*S40G|SPECTRIX.*S40G|XPG_SPECTRIX_S40G|$KNOWN_MAIN_SERIAL" <<<"$text"; then
    return 0
  fi
  # Conservative fallback: 1.7T-2.3T NVMe, not the M500 media disk.
  if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 1700000000000 && bytes < 2300000000000 )); then
    if ! looks_like_media_nvme "$text"; then
      return 0
    fi
  fi
  return 1
}

looks_like_media_nvme() {
  local text="$*"
  grep -Eiq "(MLD|MDL).*M500|M500.*NVMe|M500_NVMe|$KNOWN_MLD_SERIAL" <<<"$text"
}

print_debug() {
  echo
  echo "===== NVMe debug inventory ====="
  echo "--- pvesm status ---"; pvesm status 2>/dev/null || true
  echo "--- zpool list ---"; zpool list 2>/dev/null || true
  echo "--- zpool import ---"; zpool import 2>/dev/null || true
  echo "--- lsblk -dn -P -o NAME,MODEL,SERIAL,SIZE,TYPE ---"; lsblk -dn -P -o NAME,MODEL,SERIAL,SIZE,TYPE 2>/dev/null || true
  echo "--- sysfs nvme model/serial ---"
  for d in /sys/block/nvme*n1; do
    [[ -e "$d" ]] || continue
    n="$(basename "$d")"
    echo "/dev/$n model=$(cat "$d/device/model" 2>/dev/null || true) serial=$(cat "$d/device/serial" 2>/dev/null || true) size=$(lsblk -dn -o SIZE "/dev/$n" 2>/dev/null || true) bytes=$(blockdev --getsize64 "/dev/$n" 2>/dev/null || true)"
  done
  echo "--- /dev/disk/by-id nvme entries ---"
  find /dev/disk/by-id -maxdepth 1 -type l -name 'nvme-*' -printf '%f -> %l\n' 2>/dev/null | sort || true
  echo "===== end debug ====="
  echo
}

find_disk_by_role() {
  local role="$1" dev info model serial size bytes byid text
  for dev in /dev/nvme*n1; do
    [[ -b "$dev" ]] || continue
    is_boot_or_root_disk "$dev" && { echo "⚠️ $role adayı root/boot disk olduğu için atlandı: $dev" >&2; continue; }
    info="$(dev_info "$dev")"
    IFS='|' read -r model serial size bytes byid <<<"$info"
    text="$dev $model $serial $size $byid"
    case "$role" in
      main)
        if looks_like_main_nvme "$text" "$bytes"; then echo "$dev|$model|$serial|$size|$bytes|$byid"; return 0; fi
        ;;
      media)
        if looks_like_media_nvme "$text"; then echo "$dev|$model|$serial|$size|$bytes|$byid"; return 0; fi
        ;;
    esac
  done
  return 1
}

remove_storage_if_exists() {
  local storage="$1"
  if storage_exists "$storage" || grep -Eq "^[a-z0-9_-]+:[[:space:]]+$storage$" "$STORAGE_CFG" 2>/dev/null; then
    echo "🧹 Proxmox storage kaydı kaldırılıyor: $storage"
    pvesm remove "$storage" 2>/tmp/pvesm-remove-${storage}.err || {
      cat /tmp/pvesm-remove-${storage}.err 2>/dev/null || true
      sed -i "/^[a-z0-9_-]\+:[[:space:]]\+$storage$/,/^$/d" "$STORAGE_CFG" || true
    }
  fi
}

register_zfs_storage_if_pool_exists() {
  local storage="$1" pool="${2:-$1}"
  if storage_exists "$storage"; then
    echo "✅ $storage Proxmox storage mevcut."
    return 0
  fi
  if ! zpool_exists "$pool" && importable_zpool_exists "$pool"; then
    echo "ℹ️ ZFS pool '$pool' import ediliyor."
    zpool import -f "$pool" || true
  fi
  if zpool_exists "$pool"; then
    echo "🔧 Proxmox storage kaydı ekleniyor/doğrulanıyor: $storage -> $pool"
    pvesm add zfspool "$storage" -pool "$pool" -content images,rootdir -sparse 1 2>/tmp/pvesm-add-${storage}.err || {
      grep -qi 'already exists' /tmp/pvesm-add-${storage}.err 2>/dev/null || cat /tmp/pvesm-add-${storage}.err 2>/dev/null || true
    }
    storage_exists "$storage" && { echo "✅ $storage hazır."; return 0; }
  fi
  return 1
}

stop_destroy_known_vms() {
  local vmid
  echo "🧨 Fresh storage reset: bilinen VM config'leri durdurulup temizleniyor..."
  for vmid in 101 102 103 104 105 106 107 110; do
    qm stop "$vmid" 2>/dev/null || true
    qm destroy "$vmid" --purge 2>/dev/null || true
    rm -f "/etc/pve/qemu-server/${vmid}.conf" 2>/dev/null || true
  done
}

destroy_pool_if_exists() {
  local pool="$1"
  if zpool_exists "$pool"; then
    echo "🧨 ZFS pool destroy: $pool"
    zpool destroy -f "$pool" || { echo "❌ ZFS pool silinemedi: $pool"; zpool status "$pool" || true; return 1; }
  fi
  if importable_zpool_exists "$pool"; then
    echo "ℹ️ Importable stale pool bulundu, import + destroy deneniyor: $pool"
    zpool import -f "$pool" || true
    zpool_exists "$pool" && zpool destroy -f "$pool" || true
  fi
}

wipe_disk() {
  local dev="$1" label="$2"
  [[ -b "$dev" ]] || { echo "❌ Disk bulunamadı: $dev"; return 1; }
  is_boot_or_root_disk "$dev" && { echo "❌ Güvenlik freni: $dev root/boot diski. Wipe edilmeyecek."; return 1; }
  is_sata_or_hdd "$dev" && { echo "❌ Güvenlik freni: $dev NVMe değil. Wipe edilmeyecek."; return 1; }

  echo "🧹 $label disk wipe ediliyor: $dev"
  zpool labelclear -f "$dev" 2>/dev/null || true
  wipefs -a "$dev" || true
  sgdisk --zap-all "$dev" || true
  # First/last MiB: stale partition/ZFS metadata için ek temizlik.
  dd if=/dev/zero of="$dev" bs=1M count=16 conv=fsync status=none || true
  local sectors size seek
  size="$(blockdev --getsz "$dev" 2>/dev/null || echo 0)"
  if [[ "$size" =~ ^[0-9]+$ ]] && (( size > 65536 )); then
    seek=$(( size/2048 - 16 ))
    dd if=/dev/zero of="$dev" bs=1M seek="$seek" count=16 conv=fsync status=none || true
  fi
  partprobe "$dev" 2>/dev/null || true
  sleep 2
}

create_pool_and_storage() {
  local storage="$1" pool="$2" dev="$3"
  echo "🧊 ZFS pool oluşturuluyor: $pool -> $dev"
  zpool create -f -o ashift=12 -O compression=lz4 -O atime=off "$pool" "$dev"
  echo "🔧 Proxmox storage ekleniyor: $storage"
  pvesm add zfspool "$storage" -pool "$pool" -content images,rootdir -sparse 1
  storage_exists "$storage" || { echo "❌ $storage pvesm doğrulaması başarısız."; return 1; }
}

if [[ "$DESTRUCTIVE_RESET" == "1" ]]; then
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y gdisk zfsutils-linux nvme-cli >/dev/null 2>&1 || true

  MAIN_FOUND="$(find_disk_by_role main || true)"
  MEDIA_FOUND="$(find_disk_by_role media || true)"
  if [[ -z "$MAIN_FOUND" || -z "$MEDIA_FOUND" ]]; then
    echo "❌ Hedef NVMe disklerden biri bulunamadı."
    [[ -z "$MAIN_FOUND" ]] && echo "   Eksik: nvme-vm için 2TB XPG SPECTRIX S40G NVMe"
    [[ -z "$MEDIA_FOUND" ]] && echo "   Eksik: nvme-vm-two için MLD/MDL/M500 NVMe"
    print_debug
    exit 1
  fi

  IFS='|' read -r MAIN_DEV MAIN_MODEL MAIN_SERIAL MAIN_SIZE MAIN_BYTES MAIN_BYID <<<"$MAIN_FOUND"
  IFS='|' read -r MEDIA_DEV MEDIA_MODEL MEDIA_SERIAL MEDIA_SIZE MEDIA_BYTES MEDIA_BYID <<<"$MEDIA_FOUND"
  if [[ "$MAIN_DEV" == "$MEDIA_DEV" ]]; then
    echo "❌ Güvenlik freni: nvme-vm ve nvme-vm-two aynı diske çözündü: $MAIN_DEV"
    print_debug
    exit 1
  fi

  echo
  echo "✅ Fresh storage hedefleri:"
  echo "  nvme-vm     : $MAIN_DEV / $MAIN_MODEL / $MAIN_SERIAL / $MAIN_SIZE / $MAIN_BYID"
  echo "  nvme-vm-two : $MEDIA_DEV / $MEDIA_MODEL / $MEDIA_SERIAL / $MEDIA_SIZE / $MEDIA_BYID"
  echo

  stop_destroy_known_vms
  remove_storage_if_exists "$TARGET_MAIN_STORAGE"
  remove_storage_if_exists "$TARGET_MEDIA_STORAGE"
  destroy_pool_if_exists "$TARGET_MAIN_POOL"
  destroy_pool_if_exists "$TARGET_MEDIA_POOL"
  wipe_disk "$MAIN_DEV" "$TARGET_MAIN_STORAGE"
  wipe_disk "$MEDIA_DEV" "$TARGET_MEDIA_STORAGE"
  create_pool_and_storage "$TARGET_MAIN_STORAGE" "$TARGET_MAIN_POOL" "$MAIN_DEV"
  create_pool_and_storage "$TARGET_MEDIA_STORAGE" "$TARGET_MEDIA_POOL" "$MEDIA_DEV"
else
  echo
  echo "💽 Safe register kontrolü: $TARGET_MAIN_STORAGE"
  register_zfs_storage_if_pool_exists "$TARGET_MAIN_STORAGE" "$TARGET_MAIN_POOL" || echo "ℹ️ $TARGET_MAIN_STORAGE hazır değil; destructive guided reset veya manuel maintenance seçeneğiyle oluşturulmalı."
  echo
  echo "💽 Safe register kontrolü: $TARGET_MEDIA_STORAGE"
  register_zfs_storage_if_pool_exists "$TARGET_MEDIA_STORAGE" "$TARGET_MEDIA_POOL" || echo "ℹ️ $TARGET_MEDIA_STORAGE hazır değil; destructive guided reset veya manuel maintenance seçeneğiyle oluşturulmalı."
fi

echo
echo "===== Yeni storage.cfg ====="
cat "$STORAGE_CFG"
echo
echo "===== Proxmox storage durumu ====="
pvesm status || true
echo
echo "✅ Storage normalize tamamlandı."
