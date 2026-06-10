#!/usr/bin/env bash
set -Eeuo pipefail

STATE="${HOMELABV4_STATE:-/opt/homelabv4/state}"
MARKER="$STATE/proxmox-update-reboot.env"
DONE="$STATE/proxmox-update.done"
BACKUP_DIR="/root/homelab-backups/apt-sources"
REBOOT_EXIT_CODE=194

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

say() { printf '%s\n' "$*"; }

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    say "ERROR: Proxmox update must run as root."
    exit 1
  fi
}

current_boot_id() {
  cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown
}

latest_installed_pve_kernel() {
  find /boot -maxdepth 1 -type f -name 'vmlinuz-*-pve' -printf '%f\n' 2>/dev/null \
    | sed 's/^vmlinuz-//' \
    | sort -V \
    | tail -n 1
}

need_safe_reboot() {
  [[ -f /var/run/reboot-required ]] && return 0
  local running latest
  running="$(uname -r)"
  latest="$(latest_installed_pve_kernel || true)"
  [[ -n "$latest" && "$running" != "$latest" ]]
}

backup_apt_file() {
  local file="$1"
  mkdir -p "$BACKUP_DIR"
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$(basename "$file").backup.$(date +%Y%m%d-%H%M%S)" || true
}

disable_enterprise_repos() {
  local file
  say "[1/5] Disabling Proxmox enterprise repositories if present."

  for file in /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/ceph.list; do
    if [[ -f "$file" ]]; then
      backup_apt_file "$file"
      sed -i -E 's|^[[:space:]]*deb[[:space:]]|# deb |g' "$file" || true
      say "Disabled list repo: $file"
    fi
  done

  for file in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
    if [[ -f "$file" ]]; then
      backup_apt_file "$file"
      if grep -q '^Enabled:' "$file"; then
        sed -i -E 's|^Enabled:.*|Enabled: no|g' "$file" || true
      else
        printf '\nEnabled: no\n' >> "$file"
      fi
      say "Disabled deb822 repo: $file"
    fi
  done
}

ensure_no_subscription_repo() {
  local codename
  codename="$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION_CODENAME:-trixie}")"
  [[ -n "$codename" ]] || codename="trixie"

  say "[2/5] Ensuring Proxmox no-subscription repository for ${codename}."
  cat > /etc/apt/sources.list.d/pve-no-subscription.list <<APT
deb http://download.proxmox.com/debian/pve ${codename} pve-no-subscription
APT
}

wait_for_apt_locks() {
  local lock
  for _ in $(seq 1 120); do
    local busy=0
    for lock in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock /var/lib/apt/lists/lock; do
      if command -v fuser >/dev/null 2>&1 && fuser "$lock" >/dev/null 2>&1; then
        busy=1
      fi
    done
    [[ "$busy" -eq 0 ]] && return 0
    say "APT/dpkg lock is busy; waiting..."
    sleep 5
  done
  say "WARNING: APT locks still look busy; continuing carefully."
}

run_update() {
  say "[3/5] Cleaning APT cache and updating package index."
  wait_for_apt_locks
  apt-get clean || true
  rm -rf /var/lib/apt/lists/* || true
  apt-get update

  say "[4/5] Installing base Proxmox/Homelab tools."
  apt-get install -y \
    curl wget git sudo nano jq unzip net-tools htop ifupdown2 \
    ca-certificates gnupg lsb-release python3 dos2unix rsync sshpass \
    openssh-client openssh-server iputils-ping dnsutils tar gzip \
    gdisk zfsutils-linux whiptail dialog less smartmontools nvme-cli nmap arp-scan

  say "[5/5] Running system dist-upgrade."
  apt-get -y dist-upgrade
}

write_done() {
  mkdir -p "$STATE"
  {
    echo "completedAt=$(date -Iseconds)"
    echo "bootId=$(current_boot_id)"
    echo "kernel=$(uname -r)"
  } > "$DONE"
}

handle_reboot_gate() {
  local boot_id previous_boot=""
  boot_id="$(current_boot_id)"

  if [[ -f "$MARKER" ]]; then
    # shellcheck disable=SC1090
    source "$MARKER" || true
    previous_boot="${REBOOT_REQUESTED_BOOT_ID:-}"
    if [[ -n "$previous_boot" && "$previous_boot" != "$boot_id" ]]; then
      say "Detected that Proxmox rebooted after the previous update request."
      rm -f "$MARKER"
      write_done
      return 0
    fi
  fi

  if need_safe_reboot; then
    mkdir -p "$STATE"
    {
      echo "REBOOT_REQUESTED_AT=$(date -Iseconds)"
      echo "REBOOT_REQUESTED_BOOT_ID=$boot_id"
      echo "REBOOT_REQUESTED_KERNEL=$(uname -r)"
    } > "$MARKER"
    say
    say "PROXMOX_REBOOT_REQUESTED"
    say "Kernel/PVE update installed. Proxmox will reboot in a few seconds."
    say "After the host comes back, open the tunnel again and run Smart Install or Full Install; this step will be skipped."
    sync || true
    ( sleep 8; systemctl reboot ) >/tmp/homelabv4-proxmox-update-reboot.log 2>&1 &
    exit "$REBOOT_EXIT_CODE"
  fi

  rm -f "$MARKER"
  write_done
}

need_root

say "Homelabv4 Proxmox update and reboot gate"
say "Current kernel: $(uname -r)"

if [[ -f "$DONE" && ! -f "$MARKER" && "${HOMELABV4_FORCE_PROXMOX_UPDATE:-0}" != "1" ]]; then
  say "Proxmox update marker already exists: $DONE"
  say "Set HOMELABV4_FORCE_PROXMOX_UPDATE=1 to force another update pass."
  exit 0
fi

if [[ -f "$MARKER" ]]; then
  handle_reboot_gate
  if [[ -f "$DONE" && ! -f "$MARKER" ]]; then
    exit 0
  fi
fi

disable_enterprise_repos
ensure_no_subscription_repo
run_update
handle_reboot_gate

say "Proxmox update completed without requiring reboot."
