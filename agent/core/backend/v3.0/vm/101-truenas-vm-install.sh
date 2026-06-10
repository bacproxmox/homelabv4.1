#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils/env-loader.sh"
source "$ROOT_DIR/utils/logging.sh"
start_log "vm-101-truenas"
require_root
load_all_env

VMID="101"
VMNAME="truenas"
STORAGE="${VM_STORAGE:-nvme-vm}"

# Canonical Homelab v2.4.6 hardware IDs. Do not ask unless hardware really changed.
NVME="${PVE_NVME_DISK:-/dev/disk/by-id/nvme-XPG_SPECTRIX_S40G_2J4520139863}"
DISK_TANK="${TRUENAS_TANK_DISK:-/dev/disk/by-id/ata-TOSHIBA_MG10ACA20TE_4580A0BSF4MJ}"
DISK_PRIVATE="${TRUENAS_PRIVATE_DISK:-/dev/disk/by-id/ata-ST4000NM0053_Z1Z5KNAT}"
TRUENAS_PRIVATE_REQUIRED="${TRUENAS_PRIVATE_REQUIRED:-0}"

ISO_DIR="/var/lib/vz/template/iso"
TRUENAS_DOWNLOAD_PAGE="https://www.truenas.com/download/"
TRUENAS_CODENAME="${TRUENAS_CODENAME:-Goldeye}"
TRUENAS_VM_RAM="${TRUENAS_VM_RAM:-16384}"
TRUENAS_OS_DISK="${TRUENAS_OS_DISK:-64}"
TRUENAS_FIXED_MAC="${TRUENAS_FIXED_MAC:-${VM101_MAC:-02:23:14:00:01:01}}"

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Eksik komut: $1"; exit 1; }; }
fail_disk_missing() {
  local label="$1" path="$2"
  echo "❌ $label bulunamadı: $path"
  echo
  echo "Mevcut diskler:"
  lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,TRAN | sed 's/^/  /'
  echo
  echo "/dev/disk/by-id listesi:"
  find /dev/disk/by-id -maxdepth 1 -type l | sort | sed 's/^/  /'
  exit 1
}
assert_not_nvme_passthrough() {
  local disk="$1"
  if [[ "$disk" == *nvme* || "$disk" == "$NVME" ]]; then
    echo "❌ Güvenlik blokajı: TrueNAS passthrough için NVMe seçilemez: $disk"
    exit 1
  fi
}
private_required() {
  case "${TRUENAS_PRIVATE_REQUIRED:-0}" in
    1|true|True|TRUE|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}
normalize_local_storage() {
  if [[ -x "$ROOT_DIR/bootstrap/02-normalize-local-storage.sh" ]]; then
    bash "$ROOT_DIR/bootstrap/02-normalize-local-storage.sh" || true
  fi
}

cat <<HEADER

🧊 Homelab v2.4.7 - TrueNAS VM 101 oluşturma
Storage              : $STORAGE
VM storage NVMe      : $NVME
TrueNAS tank disk    : $DISK_TANK
TrueNAS private disk : $DISK_PRIVATE
TrueNAS fixed MAC   : $TRUENAS_FIXED_MAC
ÖNEMLİ               : NVMe TrueNAS'a passthrough edilmeyecek. Sadece 20TB + 4TB SATA diskleri bağlanacak.

HEADER

apt update
apt install -y curl wget ca-certificates grep gawk coreutils gdisk zfsutils-linux
for c in curl wget awk grep sort qm pvesm zpool zfs wipefs sgdisk; do need_cmd "$c"; done

normalize_local_storage

[[ -e "$NVME" ]] || fail_disk_missing "XPG SPECTRIX S40G NVMe" "$NVME"
[[ -e "$DISK_TANK" ]] || fail_disk_missing "20TB tank disk" "$DISK_TANK"
assert_not_nvme_passthrough "$DISK_TANK"
if private_required; then
  [[ -e "$DISK_PRIVATE" ]] || fail_disk_missing "4TB private disk" "$DISK_PRIVATE"
  assert_not_nvme_passthrough "$DISK_PRIVATE"
else
  echo "TRUENAS_PRIVATE_REQUIRED=0; 4TB private passthrough is skipped."
fi

echo
 echo "💾 NVMe storage kontrol ediliyor: $STORAGE"
if ! zpool list "$STORAGE" >/dev/null 2>&1; then
  echo "⚠️ ZFS pool oluşturulacak: $STORAGE"
  echo "⚠️ Disk temizlenecek: $NVME"
  echo "Bu disk VM storage içindir; TrueNAS'a passthrough edilmeyecek."
  sleep 5
  wipefs -a "$NVME" || true
  sgdisk --zap-all "$NVME" || true
  zpool create -f -o ashift=12 "$STORAGE" "$NVME"
  zfs set compression=lz4 "$STORAGE"
  zfs set atime=off "$STORAGE"
  echo "✅ ZFS pool oluşturuldu: $STORAGE"
else
  echo "✅ ZFS pool zaten var: $STORAGE"
fi

if ! pvesm status | awk '{print $1}' | grep -qx "$STORAGE"; then
  echo "➕ Proxmox storage ekleniyor: $STORAGE"
  pvesm add zfspool "$STORAGE" -pool "$STORAGE" -content images,rootdir
else
  echo "✅ Proxmox storage zaten var: $STORAGE"
fi

echo
 echo "📀 En güncel stable TrueNAS SCALE sürümü aranıyor..."
LATEST_VERSION="$(curl -fsSL "$TRUENAS_DOWNLOAD_PAGE" | grep -Eo '[0-9]{2}\.[0-9]{2}\.[0-9]+(\.[0-9]+)?(-[A-Za-z0-9.]+)?' | grep -v -Ei 'BETA|RC|ALPHA|NIGHTLY|MASTER' | sort -V | tail -n 1 || true)"
[[ -n "$LATEST_VERSION" ]] || { echo "❌ TrueNAS stable sürümü otomatik bulunamadı."; exit 1; }
ISO_FILE="TrueNAS-SCALE-${LATEST_VERSION}.iso"
LOCAL_ISO="$ISO_DIR/$ISO_FILE"
PVE_ISO="local:iso/$ISO_FILE"
LATEST_ISO_URL="https://download.sys.truenas.net/TrueNAS-SCALE-${TRUENAS_CODENAME}/${LATEST_VERSION}/TrueNAS-SCALE-${LATEST_VERSION}.iso"

echo "✅ Bulunan stable sürüm: $LATEST_VERSION"
echo "✅ ISO URL: $LATEST_ISO_URL"
mkdir -p "$ISO_DIR"
[[ -f "$LOCAL_ISO" ]] || wget -O "$LOCAL_ISO" "$LATEST_ISO_URL"

echo
 echo "🧊 TrueNAS VM oluşturuluyor/güncelleniyor..."
if qm status "$VMID" >/dev/null 2>&1; then
  if qm status "$VMID" | grep -q running; then
    echo "❌ VM $VMID çalışıyor. Donanım güncellemek için önce kapat: qm shutdown $VMID"
    exit 1
  fi
  echo "✅ VM $VMID zaten var; donanım ayarları doğrulanacak."
else
  qm create "$VMID"     --name "$VMNAME"     --memory "$TRUENAS_VM_RAM"     --cores 4     --cpu host     --machine q35     --bios ovmf     --scsihw virtio-scsi-single     --net0 "virtio=${TRUENAS_FIXED_MAC},bridge=vmbr0"     --onboot 1     --balloon 0     --vga vmware
fi

# Idempotent hardware enforcement. Eski scriptte çalışan mimari: scsi0 OS, ide2 ISO, scsi1/scsi2 raw SATA passthrough.
qm set "$VMID" --net0 "virtio=${TRUENAS_FIXED_MAC},bridge=vmbr0"
qm set "$VMID" --efidisk0 "$STORAGE":1,format=raw,efitype=4m
qm set "$VMID" --scsi0 "$STORAGE":"$TRUENAS_OS_DISK",discard=on,ssd=1,iothread=1
qm set "$VMID" --ide2 "$PVE_ISO",media=cdrom
qm set "$VMID" --boot order=ide2
qm set "$VMID" --scsi1 "$DISK_TANK",serial=TANK20TB
if private_required; then
  qm set "$VMID" --scsi2 "$DISK_PRIVATE",serial=PRIVATE4TB
else
  qm set "$VMID" --delete scsi2 >/dev/null 2>&1 || true
fi

CFG="$(qm config "$VMID")"
echo "$CFG"
if ! private_required; then
  CFG="${CFG}"$'\n'"scsi2: $DISK_PRIVATE,optional-private-skipped"
fi

echo
 echo "🔎 VM101 doğrulama..."
echo "$CFG" | grep -q '^ide2: local:iso/TrueNAS-SCALE-' || { echo "❌ ISO ide2 üzerinde local:iso/... olarak bağlı değil."; exit 1; }
echo "$CFG" | grep -q "^scsi1: $DISK_TANK" || { echo "❌ scsi1 20TB tank passthrough bağlı değil."; exit 1; }
echo "$CFG" | grep -q "^scsi2: $DISK_PRIVATE" || { echo "❌ scsi2 4TB private passthrough bağlı değil."; exit 1; }
if echo "$CFG" | grep -E '^scsi[12]:' | grep -q 'nvme'; then
  echo "❌ Güvenlik hatası: NVMe scsi1/scsi2 passthrough olarak görünüyor."
  exit 1
fi

echo "✅ VM101 ISO + passthrough doğrulaması tamam."

cat <<NEXT

✅ TrueNAS VM 101 hazır.

v2.4.6 akışı:
- Install Menu seçenek 3 ve Guided Pipeline artık aynı checkpoint mantığını kullanır.
- Bu script menüden çağrıldıysa sıradaki ekranda "TrueNAS kurulumu bitti mi?" sorusu gelecek.
- VM101 installer otomatik başlatılır; Console > installer içinde SADECE ${TRUENAS_OS_DISK}GB OS diskini seç.
- Kurulum bittiğinde menüde YES/y yaz; script ISO/CD'yi kaldırır, boot'u scsi0 yapar, VM101'i yeniden başlatır.
- Sonra WebUI + SSH testleri yapılır.

Router DHCP reservation önerisi:
  ${TRUENAS_FIXED_MAC} -> 192.168.50.101

Eğer bu dosyayı standalone çalıştırdıysan menüye dönüp seçenek 3'ü tekrar seç veya seçenek 4 öncesi VM101'in disk boot + SSH hazır olduğundan emin ol.
NEXT
