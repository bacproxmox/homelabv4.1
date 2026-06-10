#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${HOMELAB_ROOT:-}" ]]; then
  HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

source "$HOMELAB_ROOT/lib/core/env.sh"
source "$HOMELAB_ROOT/lib/core/state.sh"
load_all_env

TRUENAS_VMID="${TRUENAS_VMID:-101}"
TRUENAS_VMNAME="${TRUENAS_VMNAME:-truenas}"
TRUENAS_VM_STORAGE="${VM_STORAGE:-${TRUENAS_VM_STORAGE:-nvme-vm}}"
PVE_NVME_DISK="${PVE_NVME_DISK:-/dev/disk/by-id/nvme-XPG_SPECTRIX_S40G_2J4520139863}"
TRUENAS_TANK_DISK="${TRUENAS_TANK_DISK:-/dev/disk/by-id/ata-TOSHIBA_MG10ACA20TE_4580A0BSF4MJ}"
TRUENAS_PRIVATE_DISK="${TRUENAS_PRIVATE_DISK:-/dev/disk/by-id/ata-ST4000NM0053_Z1Z5KNAT}"
TRUENAS_PRIVATE_REQUIRED="${TRUENAS_PRIVATE_REQUIRED:-0}"
TRUENAS_ISO_DIR="${TRUENAS_ISO_DIR:-/var/lib/vz/template/iso}"
TRUENAS_DOWNLOAD_PAGE="${TRUENAS_DOWNLOAD_PAGE:-https://www.truenas.com/download/}"
TRUENAS_CODENAME="${TRUENAS_CODENAME:-Goldeye}"
TRUENAS_VM_RAM="${TRUENAS_VM_RAM:-16384}"
TRUENAS_OS_DISK="${TRUENAS_OS_DISK:-64}"
TRUENAS_FIXED_MAC="${TRUENAS_FIXED_MAC:-${VM101_MAC:-02:23:14:00:01:01}}"
TRUENAS_ISO_STATE="${TRUENAS_ISO_STATE:-$STATE_DIR/truenas-iso.env}"

truenas_fail_disk_missing() {
  local label="$1" path="$2"
  echo "❌ TrueNAS disk preflight durdu: $label bulunamadi."
  echo "Beklenen path:"
  echo "  $path"
  echo
  echo "Mevcut diskler:"
  lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,TRAN,FSTYPE,LABEL | sed 's/^/  /' || true
  echo
  echo "/dev/disk/by-id listesi:"
  find /dev/disk/by-id -maxdepth 1 -type l | sort | sed 's/^/  /' || true
  echo
  echo "Recovery kontrol komutlari:"
  echo "  ls -l /dev/disk/by-id | grep -Ei 'ST4000|Z1Z5|Seagate|TOSHIBA|MG10|PRIVATE|TANK' || true"
  echo "  lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,FSTYPE,LABEL"
  echo "  dmesg -T | grep -Ei 'ata|resetting link|I/O error|failed command|ST4000|Seagate' | tail -120"
  echo
  echo "Not: Script guvenlik icin otomatik alternatif disk secmez."
  echo "Dogru disk path'ini biliyorsan env override kullanabilirsin:"
  echo "  export TRUENAS_TANK_DISK=/dev/disk/by-id/..."
  echo "  export TRUENAS_PRIVATE_DISK=/dev/disk/by-id/..."
  if [[ "$label" == *private* || "$label" == *Private* || "$label" == *4TB* ]]; then
    echo
    echo "Private pool olmadan bilincli devam etmek istersen:"
    echo "  export TRUENAS_PRIVATE_REQUIRED=0"
    echo "Bu durumda private SMB/share ve private/Immich entegrasyonlari sonradan maintenance ile tamamlanmali."
  fi
  exit 1
}

truenas_assert_not_nvme_passthrough() {
  local disk="$1"
  if [[ "$disk" == *nvme* || "$disk" == "$PVE_NVME_DISK" ]]; then
    echo "Hata: TrueNAS passthrough icin NVMe secilemez: $disk"
    exit 1
  fi
}

truenas_discover_latest_version() {
  curl -fsSL "$TRUENAS_DOWNLOAD_PAGE" \
    | grep -Eo '[0-9]{2}\.[0-9]{2}\.[0-9]+(\.[0-9]+)?(-[A-Za-z0-9.]+)?' \
    | grep -v -Ei 'BETA|RC|ALPHA|NIGHTLY|MASTER' \
    | sort -V \
    | tail -n 1
}

truenas_write_iso_state() {
  local version="$1"
  local iso_file="TrueNAS-SCALE-${version}.iso"
  local local_iso="$TRUENAS_ISO_DIR/$iso_file"
  local pve_iso="local:iso/$iso_file"
  local iso_url="https://download.sys.truenas.net/TrueNAS-SCALE-${TRUENAS_CODENAME}/${version}/TrueNAS-SCALE-${version}.iso"

  mkdir -p "$STATE_DIR"
  cat > "$TRUENAS_ISO_STATE" <<ENV
TRUENAS_LATEST_VERSION=$version
TRUENAS_ISO_FILE=$iso_file
TRUENAS_LOCAL_ISO=$local_iso
TRUENAS_PVE_ISO=$pve_iso
TRUENAS_ISO_URL=$iso_url
ENV
}

truenas_load_iso_state() {
  if [[ ! -f "$TRUENAS_ISO_STATE" ]]; then
    local version
    version="$(truenas_discover_latest_version)"
    [[ -n "$version" ]] || {
      echo "Hata: TrueNAS stable surumu otomatik bulunamadi."
      exit 1
    }
    truenas_write_iso_state "$version"
  fi
  # shellcheck disable=SC1090
  source "$TRUENAS_ISO_STATE"
}

truenas_private_required() {
  case "${TRUENAS_PRIVATE_REQUIRED:-0}" in
    1|true|True|TRUE|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

truenas_validate_disks() {
  [[ -e "$PVE_NVME_DISK" ]] || truenas_fail_disk_missing "XPG SPECTRIX S40G NVMe" "$PVE_NVME_DISK"
  [[ -e "$TRUENAS_TANK_DISK" ]] || truenas_fail_disk_missing "20TB tank disk" "$TRUENAS_TANK_DISK"
  truenas_assert_not_nvme_passthrough "$TRUENAS_TANK_DISK"

  if [[ -e "$TRUENAS_PRIVATE_DISK" ]]; then
    truenas_assert_not_nvme_passthrough "$TRUENAS_PRIVATE_DISK"
  elif truenas_private_required; then
    truenas_fail_disk_missing "4TB private disk" "$TRUENAS_PRIVATE_DISK"
  else
    echo "⚠️ TRUENAS_PRIVATE_REQUIRED=0; private passthrough diski bulunmasa bile tank-only devam edilecek."
    echo "   Eksik private path: $TRUENAS_PRIVATE_DISK"
  fi
}
