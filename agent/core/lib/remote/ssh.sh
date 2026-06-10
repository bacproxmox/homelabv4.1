#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${HOMELAB_ROOT:-}" ]]; then
  HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

source "$HOMELAB_ROOT/lib/core/env.sh"
load_all_env

SSH_USER="${SSH_USER:-${BACMASTER_USER:-bacmaster}}"
SSH_PASS="${SSH_PASS:-${BACMASTER_PASS:-}}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/root/.ssh/known_hosts -o ConnectTimeout=8)
SSH_KEY_OPTS=(-o BatchMode=yes "${SSH_OPTS[@]}")
SSH_PASSWORD_OPTS=(-o PreferredAuthentications=password -o PubkeyAuthentication=no "${SSH_OPTS[@]}")

vm_ip() {
  case "$1" in
    101) echo 192.168.50.101 ;;
    102) echo 192.168.50.102 ;;
    103) echo 192.168.50.103 ;;
    104) echo 192.168.50.104 ;;
    105) echo 192.168.50.105 ;;
    106) echo 192.168.50.106 ;;
    107) echo 192.168.50.107 ;;
    110) echo 192.168.50.110 ;;
    *) echo "$1" ;;
  esac
}

rssh() {
  local target
  target="$(vm_ip "$1")"
  shift
  ssh_try "$target" "$@"
}

rscp() {
  local src="$1" dst_vm="$2" dst="$3" ip
  ip="$(vm_ip "$dst_vm")"
  scp_try "$src" "$ip" "$dst"
}

can_password_ssh() {
  [[ -n "$SSH_PASS" ]] && command -v sshpass >/dev/null 2>&1
}

ssh_try() {
  local ip="$1"
  shift
  if ssh "${SSH_KEY_OPTS[@]}" "$SSH_USER@$ip" "$@" 2>/tmp/homelab-ssh-key.err; then
    return 0
  fi
  if can_password_ssh && sshpass -p "$SSH_PASS" ssh "${SSH_PASSWORD_OPTS[@]}" "$SSH_USER@$ip" "$@" 2>/tmp/homelab-ssh-pass.err; then
    return 0
  fi
  return 1
}

scp_try() {
  local src="$1" ip="$2" dst="$3"
  if scp "${SSH_KEY_OPTS[@]}" -r "$src" "$SSH_USER@$ip:$dst" 2>/tmp/homelab-scp-key.err; then
    return 0
  fi
  if can_password_ssh && sshpass -p "$SSH_PASS" scp "${SSH_PASSWORD_OPTS[@]}" -r "$src" "$SSH_USER@$ip:$dst" 2>/tmp/homelab-scp-pass.err; then
    return 0
  fi
  return 1
}

wait_ssh() {
  local vm="$1" ip attempt
  ip="$(vm_ip "$vm")"
  echo "SSH bekleniyor: $SSH_USER@$ip"
  for attempt in $(seq 1 "${HOMELAB_SSH_WAIT_TRIES:-90}"); do
    if ssh_try "$ip" 'echo ok' >/dev/null 2>&1; then
      echo "SSH hazir: $ip"
      return 0
    fi
    if (( attempt % 12 == 0 )); then
      echo "Hala SSH bekleniyor: $ip ($attempt/${HOMELAB_SSH_WAIT_TRIES:-90})"
    fi
    sleep "${HOMELAB_SSH_WAIT_DELAY:-5}"
  done
  echo "SSH acilamadi: $ip"
  echo "Key auth stderr:"
  sed -n '1,8p' /tmp/homelab-ssh-key.err 2>/dev/null || true
  if can_password_ssh; then
    echo "Password auth stderr:"
    sed -n '1,8p' /tmp/homelab-ssh-pass.err 2>/dev/null || true
  else
    echo "Password fallback unavailable: sshpass missing or BACMASTER_PASS/SSH_PASS empty."
  fi
  return 1
}

run_remote_script() {
  local vm="$1" script="$2" ip
  shift 2
  ip="$(vm_ip "$vm")"
  wait_ssh "$vm"
  scp_try "$script" "$ip" "/tmp/$(basename "$script")"
  ssh_try "$ip" "chmod +x /tmp/$(basename "$script") && sudo /tmp/$(basename "$script") $*"
}
