#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/bacproxmox/homelabv3.1.1-r2.git}"
INSTALL_DIR="${INSTALL_DIR:-/root/homelabv3.1.1-r2}"
BRANCH="${BRANCH:-main}"
BOOTSTRAP_MARKER="/root/.homelabv3.1.1-r2-bootstrap-reboot-done"
export HOMELAB_VERSION="3.1.1-r2"
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Hata: root olarak calistirmalisin."
  exit 1
fi

current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$current_dir/installer/tui.sh" && -f "$current_dir/bin/homelab" ]]; then
  find "$current_dir" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
  chmod +x "$current_dir/bin/homelab" 2>/dev/null || true
  echo "Homelab v3.1.1-r2 local package bulundu; TUI baslatiliyor..."
  exec bash "$current_dir/installer/tui.sh"
fi

backup_apt_file() {
  local file="$1"
  local dir="/root/homelab-backups/apt-sources"
  mkdir -p "$dir"
  [[ -f "$file" ]] && cp "$file" "$dir/$(basename "$file").backup.$(date +%Y%m%d-%H%M%S)" || true
}

latest_installed_pve_kernel() {
  find /boot -maxdepth 1 -type f -name 'vmlinuz-*-pve' -printf '%f\n' 2>/dev/null \
    | sed 's/^vmlinuz-//' \
    | sort -V \
    | tail -n1
}

need_safe_reboot() {
  [[ -f /var/run/reboot-required ]] && return 0
  local running latest
  running="$(uname -r)"
  latest="$(latest_installed_pve_kernel || true)"
  [[ -n "$latest" && "$running" != "$latest" ]]
}

safe_reboot_gate() {
  if need_safe_reboot; then
    if [[ ! -f "$BOOTSTRAP_MARKER" ]]; then
      touch "$BOOTSTRAP_MARKER"
      echo
      echo "========================================="
      echo "SYSTEM REBOOT REQUIRED"
      echo "========================================="
      echo "Kernel/PVE update sonrasi reboot etmeden VM/VFIO/Docker kurulumuna devam etmek riskli."
      echo "Sistem simdi reboot ediliyor. Reboot sonrasi bootstrap komutunu tekrar calistir."
      sleep 8
      reboot
    fi
    echo "Uyari: reboot marker mevcut; devam ediyorum. Gerekirse manuel reboot et."
  fi
}

echo "========================================="
echo " Homelab v3.1.1-r2 - Modular Bootstrap"
echo " Proxmox Prep + Repo Clone + TUI Installer"
echo "========================================="

echo
echo "[1/8] Proxmox Enterprise repository disable..."
for file in /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/ceph.list; do
  if [[ -f "$file" ]]; then
    backup_apt_file "$file"
    sed -i 's|^[[:space:]]*deb |# deb |g' "$file" || true
    echo "Disabled: $file"
  fi
done
for file in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
  if [[ -f "$file" ]]; then
    backup_apt_file "$file"
    sed -i 's|^Enabled:.*|Enabled: no|g' "$file" || true
    grep -q '^Enabled:' "$file" || echo "Enabled: no" >> "$file"
    echo "Disabled: $file"
  fi
done

echo
echo "[2/8] Proxmox no-subscription repository..."
cat > /etc/apt/sources.list.d/pve-no-subscription.list <<'APT'
deb http://download.proxmox.com/debian/pve trixie pve-no-subscription
APT

echo
echo "[3/8] Apt update + base packages..."
apt clean || true
rm -rf /var/lib/apt/lists/* || true
apt update
apt install -y \
  curl wget git sudo nano jq unzip net-tools htop ifupdown2 \
  ca-certificates gnupg lsb-release python3 dos2unix rsync sshpass \
  openssh-client openssh-server iputils-ping dnsutils tar gzip \
  gdisk zfsutils-linux whiptail dialog less smartmontools nvme-cli nmap arp-scan

echo
echo "[4/8] System upgrade..."
apt -y dist-upgrade

echo
echo "[5/8] Safe reboot gate..."
safe_reboot_gate

echo
echo "[6/8] Clone/update Homelab v3.1.1-r2 repo..."
if [[ -d "$INSTALL_DIR/.git" ]]; then
  cd "$INSTALL_DIR"
  git fetch origin "$BRANCH"
  git reset --hard "origin/$BRANCH"
else
  rm -rf "$INSTALL_DIR"
  git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi

echo
echo "[7/8] Normalize scripts..."
find "$INSTALL_DIR" -type f -name "*.sh" -exec dos2unix {} \; >/dev/null 2>&1 || true
find "$INSTALL_DIR" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
chmod +x "$INSTALL_DIR/bin/homelab" 2>/dev/null || true

echo
echo "[8/8] Start Homelab v3.1.1-r2 TUI..."
if [[ -f "$INSTALL_DIR/installer/tui.sh" ]]; then
  exec bash "$INSTALL_DIR/installer/tui.sh"
fi

echo "Hata: installer/tui.sh bulunamadi."
exit 1
