#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "pbs-service-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

: "${BACKUP_USER:=backup}"
: "${BACKUP_PASS:?BACKUP_PASS eksik. Önce Install Menu -> 1 Bootstrap secrets/env çalıştır.}"

PBS_VM="110"
PBS_IP="${PBS_IP:-192.168.50.110}"
TMP_REMOTE="/tmp/homelab-pbs-install-remote.sh"
ENV_REMOTE="/tmp/homelab-pbs.env"

sq() { printf "%s" "$1" | sed "s/'/'\\''/g; s/^/'/; s/$/'/"; }

cat > /tmp/homelab-pbs.env <<ENV
BACKUP_USER=$(sq "$BACKUP_USER")
BACKUP_PASS=$(sq "$BACKUP_PASS")
PBS_DATASTORE_NAME=${PBS_DATASTORE_NAME:-pi-pbs-a}
PBS_DATASTORE_PATH=${PBS_DATASTORE_PATH:-/mnt/pi-pbs-a}
PBS_NFS_SOURCE=${PBS_NFS_SOURCE:-192.168.50.99:/srv/pbs-a/datastore}
PBS_ALLOW_LOCAL_DATASTORE_FALLBACK=${PBS_ALLOW_LOCAL_DATASTORE_FALLBACK:-1}
ENV
chmod 600 /tmp/homelab-pbs.env

cat > /tmp/homelab-pbs-install-remote.sh <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

log(){ echo "[$(date -Is)] $*"; }
need_env(){ local v="$1"; [[ -n "${!v:-}" ]] || { echo "❌ $v eksik"; exit 1; }; }
need_env BACKUP_USER
need_env BACKUP_PASS
PBS_DATASTORE_NAME="${PBS_DATASTORE_NAME:-pi-pbs-a}"
PBS_DATASTORE_PATH="${PBS_DATASTORE_PATH:-/mnt/pi-pbs-a}"
PBS_NFS_SOURCE="${PBS_NFS_SOURCE:-192.168.50.99:/srv/pbs-a/datastore}"
PBS_ALLOW_LOCAL_DATASTORE_FALLBACK="${PBS_ALLOW_LOCAL_DATASTORE_FALLBACK:-1}"

pbs_url_reachable() {
  local url="$1" code
  code="$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || true)"
  case "$code" in
    200|401|403) echo "✅ PBS reachable: $url HTTP $code"; return 0 ;;
    *) echo "HTTP_CODE=$code for $url"; return 1 ;;
  esac
}

disable_pbs_enterprise_repos() {
  local f base stamp
  mkdir -p /root/homelab-backups/apt-sources
  stamp="$(date +%Y%m%d-%H%M%S)"
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == *.disabled* || "$base" == *.backup.* || "$base" == *.bak.* ]] && continue
    if grep -Eiq 'enterprise\.proxmox\.com/debian/pbs|pbs-enterprise' "$f" || [[ "$base" =~ pbs.*enterprise|enterprise.*pbs ]]; then
      log "🚫 Disable/move enterprise PBS source: $f"
      cp -a "$f" "/root/homelab-backups/apt-sources/${base}.backup.${stamp}" 2>/dev/null || true
      if [[ "$f" == /etc/apt/sources.list ]]; then
        sed -i -E 's|^[[:space:]]*deb([[:space:]].*enterprise\.proxmox\.com/debian/pbs.*)$|# deb\1|I' "$f" || true
      else
        mv -f "$f" "/root/homelab-backups/apt-sources/${base}.disabled.${stamp}" || true
      fi
    fi
  done
  find /etc/apt/sources.list.d -maxdepth 1 -type f \
    \( -name '*.backup.*' -o -name '*.bak.*' -o -name '*.disabled.*' \) \
    -exec mv -f {} /root/homelab-backups/apt-sources/ \; 2>/dev/null || true
}

write_single_no_subscription_repo() {
  mkdir -p /root/homelab-backups/apt-sources
  # Remove duplicate PBS no-subscription source files; keep exactly one canonical file.
  for f in /etc/apt/sources.list.d/*pbs*.sources /etc/apt/sources.list.d/*pbs*.list; do
    [[ -f "$f" ]] || continue
    if grep -Eiq 'download\.proxmox\.com/debian/pbs|pbs-no-subscription' "$f"; then
      mv -f "$f" "/root/homelab-backups/apt-sources/$(basename "$f").old.$(date +%Y%m%d-%H%M%S)" || true
    fi
  done
  wget -qO /usr/share/keyrings/proxmox-archive-keyring.gpg https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg || \
    wget -qO /usr/share/keyrings/proxmox-archive-keyring.gpg https://download.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg || true
  cat >/etc/apt/sources.list.d/proxmox-pbs-no-subscription.sources <<'PBSREPO'
Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: trixie
Components: pbs-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
PBSREPO
}

log "PBS enterprise repos apt update'den ÖNCE kapatılıyor..."
disable_pbs_enterprise_repos
write_single_no_subscription_repo

echo "[$(date -Is)] PBS root/SSH erişimi BACKUP_PASS ile ayarlanıyor..."
printf 'root:%s\n' "$BACKUP_PASS" | chpasswd
mkdir -p /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-homelab-root-login.conf <<'SSHCONF'
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
SSHCONF
systemctl enable --now ssh >/dev/null 2>&1 || systemctl enable --now sshd >/dev/null 2>&1 || true
systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true

log "PBS repo ve paketleri hazırlanıyor..."
apt-get clean || true
rm -rf /var/lib/apt/lists/* || true
apt-get update
apt-get install -y wget curl ca-certificates gnupg lsb-release jq openssh-server sudo nfs-common coreutils

# A package update can recreate source files; enforce again before installing PBS.
disable_pbs_enterprise_repos
write_single_no_subscription_repo
apt-get clean || true
rm -rf /var/lib/apt/lists/* || true
apt-get update

log "proxmox-backup-server/client kuruluyor..."
apt-get install -y proxmox-backup-server proxmox-backup-client

if ! command -v proxmox-backup-manager >/dev/null 2>&1; then
  echo "❌ proxmox-backup-manager bulunamadı; PBS server kurulumu başarısız."
  dpkg -l | grep -Ei 'proxmox-backup|pbs' || true
  exit 1
fi

log "backup Linux/PAM kullanıcısı hazırlanıyor..."
if ! id "$BACKUP_USER" >/dev/null 2>&1; then useradd -m -s /bin/bash "$BACKUP_USER"; fi
printf '%s:%s\n' "$BACKUP_USER" "$BACKUP_PASS" | chpasswd
usermod -aG sudo "$BACKUP_USER" || true

log "PBS kullanıcı/ACL ayarlanıyor: ${BACKUP_USER}@pam"
proxmox-backup-manager user create "${BACKUP_USER}@pam" --comment "Homelab backup user" 2>/dev/null || proxmox-backup-manager user update "${BACKUP_USER}@pam" --enable true 2>/dev/null || true
proxmox-backup-manager acl update / Admin --auth-id "${BACKUP_USER}@pam" || true

log "NFS datastore mount hazırlanıyor: $PBS_NFS_SOURCE -> $PBS_DATASTORE_PATH"
mkdir -p "$PBS_DATASTORE_PATH"
if ! grep -q "${PBS_NFS_SOURCE} ${PBS_DATASTORE_PATH}" /etc/fstab; then
  echo "${PBS_NFS_SOURCE} ${PBS_DATASTORE_PATH} nfs4 vers=4.2,proto=tcp,hard,noatime,_netdev,noauto,x-systemd.automount,x-systemd.device-timeout=15,x-systemd.mount-timeout=45 0 0" >> /etc/fstab
fi
systemctl daemon-reload

if ! mountpoint -q "$PBS_DATASTORE_PATH"; then
  timeout 45s mount "$PBS_DATASTORE_PATH" || true
fi

if ! mountpoint -q "$PBS_DATASTORE_PATH"; then
  echo "❌ NFS datastore mount olmadı: $PBS_DATASTORE_PATH"
  echo "   Kaynak: $PBS_NFS_SOURCE"
  if [[ "$PBS_ALLOW_LOCAL_DATASTORE_FALLBACK" == "1" ]]; then
    echo "⚠️ PBS_ALLOW_LOCAL_DATASTORE_FALLBACK=1: geçici local datastore kullanılacak."
    mkdir -p /backup/datastore/homelab
    PBS_DATASTORE_PATH="/backup/datastore/homelab"
  else
    exit 2
  fi
fi

chown backup:backup "$PBS_DATASTORE_PATH" 2>/dev/null || true
[[ -d "$PBS_DATASTORE_PATH/.chunks" ]] && chown backup:backup "$PBS_DATASTORE_PATH/.chunks" 2>/dev/null || true

ensure_datastore_cfg_entry() {
  local name="$1" path="$2" cfg="/etc/proxmox-backup/datastore.cfg"
  mkdir -p /etc/proxmox-backup
  touch "$cfg"
  if grep -Eq "^datastore:[[:space:]]+${name}$" "$cfg"; then
    echo "✅ datastore.cfg içinde mevcut: $name"
    return 0
  fi
  cp "$cfg" "${cfg}.bak.$(date +%Y%m%d-%H%M%S)" || true
  cat >> "$cfg" <<EOF2

datastore: ${name}
        path ${path}
EOF2
  echo "✅ datastore.cfg kaydı eklendi: $name -> $path"
}

log "Datastore hazırlanıyor: ${PBS_DATASTORE_NAME} -> ${PBS_DATASTORE_PATH}"
if proxmox-backup-manager datastore list --output-format json 2>/dev/null | jq -e --arg n "$PBS_DATASTORE_NAME" '.[]? | select(.name==$n)' >/dev/null 2>&1; then
  echo "✅ Datastore zaten mevcut: $PBS_DATASTORE_NAME"
else
  if [[ -d "$PBS_DATASTORE_PATH/.chunks" ]]; then
    echo "ℹ️ $PBS_DATASTORE_PATH/.chunks zaten var; mevcut PBS datastore yeniden kaydedilecek."
    ensure_datastore_cfg_entry "$PBS_DATASTORE_NAME" "$PBS_DATASTORE_PATH"
  else
    proxmox-backup-manager datastore create "$PBS_DATASTORE_NAME" "$PBS_DATASTORE_PATH" || ensure_datastore_cfg_entry "$PBS_DATASTORE_NAME" "$PBS_DATASTORE_PATH"
  fi
fi

systemctl enable --now proxmox-backup proxmox-backup-proxy
systemctl restart proxmox-backup proxmox-backup-proxy || true
sleep 3
proxmox-backup-manager datastore list || true
proxmox-backup-manager acl update "/datastore/${PBS_DATASTORE_NAME}" DatastoreAdmin --auth-id "${BACKUP_USER}@pam" || true

log "PBS 8007 bekleniyor..."
for i in {1..60}; do
  if ss -ltn | grep -q ':8007'; then break; fi
  sleep 2
done
ss -ltn | grep -q ':8007' || { echo "❌ PBS 8007 açılmadı"; systemctl --no-pager --full status proxmox-backup-proxy proxmox-backup || true; exit 1; }
pbs_url_reachable https://127.0.0.1:8007/api2/json/version || { echo "❌ PBS API local endpoint erişilemedi"; exit 1; }

echo
cat <<DONE
✅ Proxmox Backup Server kuruldu ve doğrulandı.
Web UI: https://192.168.50.110:8007
Login : ${BACKUP_USER}@pam veya root@pam
Şifre : BACKUP_PASS
Datastore: ${PBS_DATASTORE_NAME} -> ${PBS_DATASTORE_PATH}
DONE
REMOTE
chmod +x /tmp/homelab-pbs-install-remote.sh

wait_ssh "$PBS_VM"
rscp /tmp/homelab-pbs.env "$PBS_VM" "$ENV_REMOTE" >/dev/null
rscp /tmp/homelab-pbs-install-remote.sh "$PBS_VM" "$TMP_REMOTE" >/dev/null
rssh "$PBS_VM" "chmod +x '$TMP_REMOTE' && sudo bash -c 'set -a; source $ENV_REMOTE; set +a; $TMP_REMOTE; rm -f $ENV_REMOTE'"

rm -f /tmp/homelab-pbs.env /tmp/homelab-pbs-install-remote.sh

pbs_url_reachable() {
  local url="$1" code
  code="$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || true)"
  case "$code" in
    200|401|403) echo "✅ PBS reachable: $url HTTP $code"; return 0 ;;
    *) echo "HTTP_CODE=$code for $url"; return 1 ;;
  esac
}

for i in {1..30}; do
  if pbs_url_reachable "https://${PBS_IP}:8007/api2/json/version"; then
    echo "✅ PBS service install tamamlandı: https://${PBS_IP}:8007"
    exit 0
  fi
  sleep 2
done
echo "❌ PBS dış erişim validation başarısız: https://${PBS_IP}:8007"
exit 1
