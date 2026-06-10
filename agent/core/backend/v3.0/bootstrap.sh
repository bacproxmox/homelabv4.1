#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/bacproxmox/homelabv3.0.git}"
INSTALL_DIR="${INSTALL_DIR:-/root/homelabv3.0}"
BRANCH="${BRANCH:-main}"
BOOTSTRAP_MARKER="/root/.homelabv3.0-bootstrap-reboot-done"
export HOMELAB_VERSION="3.0"
export DEBIAN_FRONTEND=noninteractive

if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Root olarak çalıştırmalısın."
  exit 1
fi

backup_apt_file() {
  local f="$1"
  local d="/root/homelab-backups/apt-sources"
  mkdir -p "$d"
  [[ -f "$f" ]] && cp "$f" "$d/$(basename "$f").backup.$(date +%Y%m%d-%H%M%S)" || true
}

normalize_local_storage_inline() {
  local cfg="/etc/pve/storage.cfg"
  [[ -f "$cfg" ]] || return 0
  echo
  echo "[storage] Normalizing Proxmox local storage..."
  mkdir -p /root/homelab-backups/storage
  cp "$cfg" "/root/homelab-backups/storage/storage.cfg.backup.before-local.$(date +%F-%H%M%S)" || true
  awk '
BEGIN { skip=0 }
$0=="dir: local" { skip=1; next }
skip && NF==0 { skip=0; next }
!skip { print }
' "$cfg" > /tmp/storage.cfg.new
  cat /tmp/storage.cfg.new > "$cfg"
  sed -i \
    -e 's/^btrfs: local-system$/btrfs: local/' \
    -e 's/^btrfs: local-btrfs$/btrfs: local/' \
    "$cfg"
  pvesm status || true
}

latest_installed_pve_kernel() {
  local latest=""
  latest="$(find /boot -maxdepth 1 -type f -name 'vmlinuz-*-pve' -printf '%f\n' 2>/dev/null | sed 's/^vmlinuz-//' | sort -V | tail -n1 || true)"
  printf '%s' "$latest"
}

need_safe_reboot() {
  [[ -f /var/run/reboot-required ]] && return 0
  local running latest
  running="$(uname -r)"
  latest="$(latest_installed_pve_kernel)"
  if [[ -n "$latest" && "$running" != "$latest" ]]; then
    echo "⚠️ Kernel mismatch detected: running=$running latest-installed=$latest"
    return 0
  fi
  return 1
}

safe_reboot_gate() {
  if need_safe_reboot; then
    if [[ ! -f "$BOOTSTRAP_MARKER" ]]; then
      touch "$BOOTSTRAP_MARKER"
      echo
      echo "========================================="
      echo "⚠️ SYSTEM REBOOT REQUIRED"
      echo "========================================="
      echo "Kernel/PVE update sonrası reboot etmeden VM/VFIO/Docker kurulumuna devam etmek riskli."
      echo
      echo "Sistem şimdi reboot ediliyor. Reboot sonrası aynı komutu tekrar çalıştır:"
      echo "bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv3.0/main/bootstrap.sh)"
      echo
      sleep 8
      reboot
    else
      echo "⚠️ Reboot marker mevcut ama reboot gerekliliği hâlâ görünüyor. Devam ediyorum; gerekirse manuel reboot et."
    fi
  fi
}

echo "========================================="
echo " Homelab v3.0 - Bootstrap"
echo " Proxmox Prep + Repo Clone + TUI Installer"
echo "========================================="

echo
echo "[1/11] Disabling Proxmox Enterprise repositories..."
for f in /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/ceph.list; do
  if [[ -f "$f" ]]; then
    backup_apt_file "$f"
    sed -i 's|^[[:space:]]*deb |# deb |g' "$f" || true
    echo "Disabled: $f"
  fi
done
for f in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
  if [[ -f "$f" ]]; then
    backup_apt_file "$f"
    sed -i 's|^Enabled:.*|Enabled: no|g' "$f" || true
    grep -q '^Enabled:' "$f" || echo "Enabled: no" >> "$f"
    echo "Disabled: $f"
  fi
done

mkdir -p /root/homelab-backups/apt-sources
find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.backup.*' -o -name '*.bak.*' \) -exec mv -f {} /root/homelab-backups/apt-sources/ \; 2>/dev/null || true

echo
echo "[2/11] Adding Proxmox no-subscription repository..."
cat > /etc/apt/sources.list.d/pve-no-subscription.list <<'APT'
deb http://download.proxmox.com/debian/pve trixie pve-no-subscription
APT

echo
echo "[3/11] Normalizing local/local-btrfs storage..."
normalize_local_storage_inline || true

echo
echo "[4/11] Cleaning apt cache..."
apt clean
rm -rf /var/lib/apt/lists/*

echo
echo "[5/11] Updating package lists..."
apt update

echo
echo "[6/11] Installing base packages..."
apt install -y \
  curl wget git sudo nano jq unzip net-tools htop ifupdown2 \
  ca-certificates gnupg lsb-release python3 dos2unix rsync sshpass \
  openssh-client openssh-server iputils-ping dnsutils tar gzip \
  gdisk zfsutils-linux whiptail dialog less

echo
echo "[7/11] Upgrading system..."
apt -y dist-upgrade

echo
echo "[8/11] Removing Proxmox no-subscription popup..."
PVE_JS="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
if [[ -f "$PVE_JS" ]]; then
  cp "$PVE_JS" "/root/homelab-backups/proxmoxlib.js.backup.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  sed -i.bak "s/Ext.Msg.show({/void({/g" "$PVE_JS" || true
  systemctl restart pveproxy || true
  echo "Popup patch attempted."
else
  echo "Warning: $PVE_JS not found, skipping popup patch."
fi

echo
echo "[9/11] Final apt check..."
apt update

echo
echo "[10/11] Safe reboot gate..."
safe_reboot_gate

echo
echo "[11/11] Cloning/updating Homelab v3.0 repo..."
if [[ -d "$INSTALL_DIR/.git" ]]; then
  cd "$INSTALL_DIR"
  git fetch origin "$BRANCH"
  git reset --hard "origin/$BRANCH"
else
  rm -rf "$INSTALL_DIR"
  git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi

find "$INSTALL_DIR" -type f -name "*.sh" -exec dos2unix {} \; >/dev/null 2>&1 || true
find "$INSTALL_DIR" -type f -name "*.sh" -exec chmod +x {} \;

echo
echo "Starting Homelab v3.0 Terminal TUI Installer..."
if [[ -x "$INSTALL_DIR/installer/v3-tui.sh" ]]; then
  bash "$INSTALL_DIR/installer/v3-tui.sh"
else
  echo "⚠️ v3 TUI bulunamadı; legacy menü açılıyor."
  bash "$INSTALL_DIR/menu/install-menu.sh"
fi
