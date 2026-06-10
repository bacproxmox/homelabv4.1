#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"
start_log "rollback-everything-except-truenas"

KEEP_VMID="101"
DESTROY_VMIDS=(102 103 104 105 106 107 110)
STATE_DIR="/root/homelab-state"

cat <<'WARN'
=========================================
 ⚠️ Homelab rollback: everything except TrueNAS
=========================================

Bu işlem VM102-VM107 ve VM110 VM'lerini durdurup silecek.

KORUNACAKLAR:
  ✅ VM101 TrueNAS
  ✅ TrueNAS passthrough diskleri/pool'ları
  ✅ Proxmox host ayarları
  ✅ nvme-vm storage/ZFS pool
  ✅ /root/homelab-secrets

SİLİNECEKLER:
  ❌ VM102 docker-arr
  ❌ VM103 network/cloudflared/uptime
  ❌ VM104 nextcloud
  ❌ VM105 homeassistant
  ❌ VM106 media-ai
  ❌ VM107 chia-farmer
  ❌ VM110 pbs-backup

WARN

if ! qm status "$KEEP_VMID" >/dev/null 2>&1; then
  echo "⚠️ VM101 TrueNAS bulunamadı. Yine de VM102-107/110 rollback yapılabilir."
else
  echo "✅ VM101 TrueNAS mevcut ve korunacak."
fi

echo
echo "Mevcut VM listesi:"
qm list || true

echo
echo "Silinecek VMID listesi: ${DESTROY_VMIDS[*]}"
read -r -p "Devam etmek için tam olarak ROLLBACK yaz: " CONFIRM
if [[ "$CONFIRM" != "ROLLBACK" ]]; then
  echo "İptal edildi."
  exit 0
fi

for vmid in "${DESTROY_VMIDS[@]}"; do
  if ! qm status "$vmid" >/dev/null 2>&1; then
    echo "ℹ️ VM $vmid yok, geçiliyor."
    continue
  fi

  echo
  echo "🛑 VM $vmid durduruluyor..."
  qm stop "$vmid" --skiplock 1 2>/dev/null || true

  for _ in {1..20}; do
    status="$(qm status "$vmid" 2>/dev/null | awk '{print $2}' || true)"
    [[ "$status" == "stopped" || -z "$status" ]] && break
    sleep 2
  done

  echo "🧨 VM $vmid siliniyor..."
  qm destroy "$vmid" --purge 1 --destroy-unreferenced-disks 1 2>/dev/null || \
    qm destroy "$vmid" --purge 1 2>/dev/null || true
done

echo
echo "🧹 SSH known_hosts temizliği..."
for ip in 192.168.50.102 192.168.50.103 192.168.50.104 192.168.50.105 192.168.50.106 192.168.50.107 192.168.50.110; do
  ssh-keygen -R "$ip" >/dev/null 2>&1 || true
done

echo
echo "🧹 State cleanup seçenekleri..."
if [[ -d "$STATE_DIR" ]]; then
  read -r -p "$STATE_DIR içindeki VM/service state dosyaları temizlensin mi? [y/N]: " CLEAN_STATE
  if [[ "$CLEAN_STATE" =~ ^[Yy]$ ]]; then
    mkdir -p "$STATE_DIR/archive"
    tar -C "$STATE_DIR" -czf "$STATE_DIR/archive/state-before-rollback-$(date +%Y%m%d-%H%M%S).tar.gz" . 2>/dev/null || true
    find "$STATE_DIR" -maxdepth 1 -type f -delete
    echo "✅ State dosyaları temizlendi."
  else
    echo "ℹ️ State korundu."
  fi
fi

echo
echo "📦 Storage kontrol:"
pvesm status || true

echo
echo "✅ Rollback tamamlandı."
echo
echo "Devam önerisi:"
echo "  cd $ROOT_DIR"
echo "  bash menu/install-menu.sh"
echo
echo "Sonra menüden:"
echo "  4) Bootstrap TrueNAS storage + install all VMs except TrueNAS"
echo "  5) Prepare all Docker hosts"
echo "  6) Install core services"
echo "  7) Configure / repair basics"
echo "  8) Phase 3 service configuration"
