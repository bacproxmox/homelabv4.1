#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${HOMELAB_ROOT:-}" ]]; then
  HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

source "$HOMELAB_ROOT/lib/core/env.sh"
source "$HOMELAB_ROOT/lib/truenas/vm101.sh"
load_all_env

TRUENAS_FINAL_IP="${TRUENAS_FINAL_IP:-${TRUENAS_HOST:-192.168.50.101}}"
TRUENAS_SUBNET="${SUBNET:-192.168.50.0/24}"

truenas_vm_mac() {
  qm config "$TRUENAS_VMID" | sed -nE 's/^net[0-9]+:.*=(([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}).*/\1/p' | head -n1 | tr '[:upper:]' '[:lower:]'
}

truenas_vm_bridge() {
  qm config "$TRUENAS_VMID" | sed -nE 's/^net[0-9]+:.*bridge=([^, ]+).*/\1/p' | head -n1
}

switch_truenas_to_disk_boot() {
  echo "TrueNAS VM${TRUENAS_VMID} installer ISO kaldiriliyor ve disk boot'a aliniyor..."
  qm stop "$TRUENAS_VMID" 2>/dev/null || true
  sleep 5
  qm set "$TRUENAS_VMID" --ide2 none || true
  qm set "$TRUENAS_VMID" --boot order=scsi0 || true
  qm start "$TRUENAS_VMID" || true
  echo "TrueNAS boot icin 60 saniye bekleniyor..."
  sleep 60
}

start_truenas_installer_if_needed() {
  if ! qm status "$TRUENAS_VMID" >/dev/null 2>&1; then
    echo "Hata: VM${TRUENAS_VMID} bulunamadi. Once VM create flow calismali."
    return 1
  fi
  if ! qm status "$TRUENAS_VMID" | grep -q running; then
    echo "VM${TRUENAS_VMID} TrueNAS installer baslatiliyor..."
    qm start "$TRUENAS_VMID" || true
    sleep 5
  fi
  echo "Proxmox UI > VM${TRUENAS_VMID} > Console ekranindan TrueNAS installer'i tamamla."
}

find_truenas_ip_by_mac() {
  local mac bridge found
  mac="$(truenas_vm_mac)"
  bridge="$(truenas_vm_bridge)"
  bridge="${bridge:-vmbr0}"
  [[ -n "$mac" ]] || return 1
  ip neigh flush all >/dev/null 2>&1 || true
  nmap -sn "$TRUENAS_SUBNET" >/dev/null 2>&1 || true
  found="$(ip neigh show | awk -v mac="$mac" 'tolower($5)==mac && $1 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ {print $1; exit}')"
  [[ -n "$found" ]] && { echo "$found"; return 0; }
  arp-scan -I "$bridge" "$TRUENAS_SUBNET" 2>/dev/null | awk -v mac="$mac" 'tolower($2)==mac && $1 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ {print $1; exit}'
}

refresh_truenas_known_host() {
  local ip="${1:-$TRUENAS_FINAL_IP}"
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  touch /root/.ssh/known_hosts
  chmod 600 /root/.ssh/known_hosts
  ssh-keygen -f /root/.ssh/known_hosts -R "$ip" >/dev/null 2>&1 || true
  ssh-keygen -f /root/.ssh/known_hosts -R "[$ip]:22" >/dev/null 2>&1 || true
  ssh-keyscan -H "$ip" >> /root/.ssh/known_hosts 2>/dev/null || true
}

test_truenas_ssh_from_login_env() {
  local ip="${1:-$TRUENAS_FINAL_IP}"
  local login_env="${SECRETS_DIR:-/root/homelab-secrets}/truenas-login.env"
  [[ -f "$login_env" ]] || return 1
  set -a
  # shellcheck disable=SC1090
  source "$login_env"
  set +a
  local user="${TRUENAS_SSH_USER:-truenas_admin}"
  local pass="${TRUENAS_SSH_PASS:-}"
  [[ -n "$pass" ]] || return 1
  refresh_truenas_known_host "$ip"
  sshpass -p "$pass" ssh \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile=/root/.ssh/known_hosts \
    -o ConnectTimeout=8 \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    "$user@$ip" 'echo SSH_OK' 2>/tmp/truenas-ssh-test.err | grep -q SSH_OK
}

truenas_checkpoint_already_done() {
  local ip="${1:-$TRUENAS_FINAL_IP}"
  if (curl -fsS --max-time 5 "http://$ip" >/dev/null 2>&1 || ping -c1 -W1 "$ip" >/dev/null 2>&1) && test_truenas_ssh_from_login_env "$ip"; then
    echo "TrueNAS disk boot + WebUI/SSH checkpoint tamam gorunuyor: $ip"
    return 0
  fi
  return 1
}

write_truenas_host_to_login_env() {
  local ip="$1"
  local login_env="${SECRETS_DIR:-/root/homelab-secrets}/truenas-login.env"
  [[ -f "$login_env" ]] || return 0
  if grep -q '^TRUENAS_HOST=' "$login_env"; then
    sed -i "s/^TRUENAS_HOST=.*/TRUENAS_HOST=$ip/" "$login_env" || true
  else
    echo "TRUENAS_HOST=$ip" >> "$login_env"
  fi
}

mark_fresh_truenas_api_required() {
  local marker="${SECRETS_DIR:-/root/homelab-secrets}/.fresh-truenas-api-required"
  mkdir -p "$(dirname "$marker")"
  touch "$marker"
  chmod 600 "$marker" 2>/dev/null || true
}

wait_for_truenas_manual_install_and_ssh() {
  local ip="$TRUENAS_FINAL_IP" ans found user pass
  local login_env="${SECRETS_DIR:-/root/homelab-secrets}/truenas-login.env"

  if truenas_checkpoint_already_done "$ip"; then
    mark_fresh_truenas_api_required
    return 0
  fi

  start_truenas_installer_if_needed || return 1

  echo
  echo "MANUEL DURAK: TrueNAS kurulumu"
  echo "1) VM101 Console'da TrueNAS installer'i manuel bitir."
  echo "2) Kurulumda SADECE ${TRUENAS_OS_DISK}GB OS diskini sec."
  echo "3) Kurulum bittiginde burada y yaz."
  while true; do
    read -r -p "TrueNAS kurulumu bitti mi? [y/N/q]: " ans
    case "$ans" in
      y|Y) break ;;
      q|Q) return 1 ;;
      *) echo "TrueNAS kurulumu icin bekleniyor..."; sleep 10 ;;
    esac
  done

  switch_truenas_to_disk_boot

  while true; do
    echo
    echo "TrueNAS WebUI kontrolu"
    echo "Oncelikli adres: http://$ip"
    echo "y = erisilebilir, ara = MAC ile IP ara, q = iptal"
    read -r -p "TrueNAS WebUI erisilebilir mi? [y/N/ara/q]: " ans
    case "$ans" in
      y|Y) break ;;
      ara|ARA)
        found="$(find_truenas_ip_by_mac || true)"
        if [[ -n "$found" ]]; then
          ip="$found"
          echo "TrueNAS aday IP bulundu: http://$ip"
        else
          echo "TrueNAS IP bulunamadi."
        fi
        ;;
      q|Q) return 1 ;;
      *) sleep 5 ;;
    esac
  done

  echo
  echo "TrueNAS WebUI > System Settings > Services > SSH > Edit:"
  echo "- Allow Password Authentication: ON"
  echo "- Password Login Groups: builtin_administrators veya truenas_admin admin grubu"
  echo "- Save"
  echo "- SSH Start"
  echo

  [[ -f "$login_env" ]] || {
    echo "Hata: eksik login env: $login_env"
    return 1
  }
  set -a
  # shellcheck disable=SC1090
  source "$login_env"
  set +a
  user="${TRUENAS_SSH_USER:-truenas_admin}"
  pass="${TRUENAS_SSH_PASS:-}"
  [[ -n "$pass" ]] || {
    echo "Hata: TRUENAS_SSH_PASS bos."
    return 1
  }

  while true; do
    read -r -p "SSH servisini actiysan y yaz. [y/N/q]: " ans
    case "$ans" in
      y|Y)
        if test_truenas_ssh_from_login_env "$ip"; then
          echo "TrueNAS SSH baglantisi basarili: $user@$ip"
          write_truenas_host_to_login_env "$ip"
          mark_fresh_truenas_api_required
          return 0
        fi
        cat /tmp/truenas-ssh-test.err 2>/dev/null || true
        echo "SSH basarisiz. SSH Running, password auth ve password login groups ayarlarini kontrol et."
        ;;
      q|Q) return 1 ;;
      *) sleep 5 ;;
    esac
  done
}
