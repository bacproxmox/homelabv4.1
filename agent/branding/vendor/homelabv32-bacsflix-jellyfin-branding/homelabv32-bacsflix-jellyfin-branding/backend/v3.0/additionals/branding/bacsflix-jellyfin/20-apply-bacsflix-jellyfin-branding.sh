#!/usr/bin/env bash
set -Eeuo pipefail
set +H

# Homelab v3.2 - Bacsflix Jellyfin branding integration
# Run from Proxmox host root, after VM106/Jellyfin has been installed.
# Usage:
#   bash 20-apply-bacsflix-jellyfin-branding.sh apply
#   bash 20-apply-bacsflix-jellyfin-branding.sh status
#   bash 20-apply-bacsflix-jellyfin-branding.sh restore

MODE="${1:-apply}"
case "$MODE" in
  apply|status|restore) ;;
  *) echo "Usage: $0 apply|status|restore"; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSET_DIR="$SCRIPT_DIR/assets"
REMOTE_SCRIPT="$SCRIPT_DIR/remote/apply-bacsflix-jellyfin-branding-inside-vm.sh"

USERS_ENV="${USERS_ENV:-/root/homelab-secrets/users.env}"
GLOBAL_ENV="${GLOBAL_ENV:-/root/homelab-secrets/global.env}"

# Defaults match the current Homelab layout: VM106 media/AI host, Jellyfin on 8096.
VM106_IP="${JELLYFIN_VM_IP:-${VM106_IP:-192.168.50.106}}"
VM106_USER="${JELLYFIN_VM_USER:-${VM106_SSH_USER:-}}"
VM106_PASS="${JELLYFIN_VM_PASS:-${VM106_SSH_PASS:-}}"

# Load Homelab secrets when available. This keeps the script usable in Guided Install and manually.
if [[ -f "$GLOBAL_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$GLOBAL_ENV"
  set +a
fi
if [[ -f "$USERS_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$USERS_ENV"
  set +a
fi

VM106_USER="${VM106_USER:-${BACMASTER_USER:-bacmaster}}"
VM106_PASS="${VM106_PASS:-${BACMASTER_PASS:-}}"
REMOTE="${JELLYFIN_REMOTE:-$VM106_USER@$VM106_IP}"
REMOTE_TMP="/tmp/homelab-bacsflix-branding-$$"

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=12
)

log(){ echo "🎬 $*"; }
warn(){ echo "⚠️  $*"; }
fail(){ echo "❌ $*"; exit 1; }
need_file(){ [[ -f "$1" ]] || fail "Gerekli dosya bulunamadı: $1"; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || fail "$1 bulunamadı"; }

need_file "$REMOTE_SCRIPT"
for asset in \
  bacsflix-logo-wallpaper.png \
  bacsflix-logo-transparent.png \
  bacsflix-icon.png \
  bacsflix-wordmark-tight.png \
  favicon.png \
  bacmaster-logo.png; do
  need_file "$ASSET_DIR/$asset"
done

need_cmd ssh
need_cmd scp

# Prefer passwordless SSH if available. Fall back to sshpass + users.env password.
SSH_PREFIX=()
SCP_PREFIX=()
if [[ -n "$VM106_PASS" ]]; then
  if ! command -v sshpass >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      log "sshpass eksik, Proxmox üzerine kuruluyor"
      apt-get update -y >/dev/null
      DEBIAN_FRONTEND=noninteractive apt-get install -y sshpass >/dev/null
    else
      fail "sshpass bulunamadı ve otomatik kurulamadı. Passwordless SSH kullan ya da sshpass kur."
    fi
  fi
  SSH_PREFIX=(sshpass -p "$VM106_PASS")
  SCP_PREFIX=(sshpass -p "$VM106_PASS")
fi

ssh_run(){ "${SSH_PREFIX[@]}" ssh "${SSH_OPTS[@]}" "$REMOTE" "$@"; }
scp_to(){ "${SCP_PREFIX[@]}" scp "${SSH_OPTS[@]}" -q "$@"; }

log "Homelab v3.2 Bacsflix Jellyfin Branding"
log "Mode   : $MODE"
log "Target : $REMOTE"
log "Assets : $ASSET_DIR"
echo

log "VM106 bağlantısı kontrol ediliyor"
ssh_run "echo HOMELAB_BACSFLIX_SSH_OK=1" >/dev/null

log "VM106 üzerinde geçici çalışma klasörü hazırlanıyor"
ssh_run "rm -rf '$REMOTE_TMP' && mkdir -p '$REMOTE_TMP/assets' '$REMOTE_TMP/remote'"

log "Bacsflix assetleri VM106'ya kopyalanıyor"
scp_to "$ASSET_DIR"/* "$REMOTE:$REMOTE_TMP/assets/"
scp_to "$REMOTE_SCRIPT" "$REMOTE:$REMOTE_TMP/remote/"

log "VM106 içinde branding işlemi çalıştırılıyor"
REMOTE_CMD="cd '$REMOTE_TMP' && chmod +x remote/apply-bacsflix-jellyfin-branding-inside-vm.sh && if [ \"\$(id -u)\" = 0 ]; then bash remote/apply-bacsflix-jellyfin-branding-inside-vm.sh '$MODE'; else echo '$VM106_PASS' | sudo -S -p '' bash remote/apply-bacsflix-jellyfin-branding-inside-vm.sh '$MODE'; fi"
ssh_run "$REMOTE_CMD"

log "Geçici klasör temizleniyor"
ssh_run "rm -rf '$REMOTE_TMP'" >/dev/null 2>&1 || true

echo
log "Bitti. Kontrol: http://$VM106_IP:8096/web/"
echo "ℹ️  Tarayıcıda Ctrl+F5 yap veya gizli sekmede aç."
