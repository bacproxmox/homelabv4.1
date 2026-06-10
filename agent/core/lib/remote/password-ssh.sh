#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${HOMELAB_ROOT:-}" ]]; then
  HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

source "$HOMELAB_ROOT/lib/core/env.sh"
load_all_env

SSH_USER="${SSH_USER:-${BACMASTER_USER:-bacmaster}}"
SSH_PASS="${SSH_PASS:-${BACMASTER_PASS:-}}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)

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

shell_quote() {
  printf '%q' "$1"
}

require_password_ssh() {
  require_cmd sshpass
  [[ -n "$SSH_PASS" ]] || {
    echo "Hata: BACMASTER_PASS/SSH_PASS yok; uzak VM profil task'i calisamaz." >&2
    exit 1
  }
}

password_rssh() {
  require_password_ssh
  local target
  target="$(vm_ip "$1")"
  shift
  sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$target" "$@"
}

password_rscp() {
  require_password_ssh
  local src="$1" dst_vm="$2" dst="$3" ip
  ip="$(vm_ip "$dst_vm")"
  sshpass -p "$SSH_PASS" scp "${SSH_OPTS[@]}" -r "$src" "$SSH_USER@$ip:$dst"
}

password_sudo_bash() {
  require_password_ssh
  local vm="$1" command="$2" pass_q
  pass_q="$(shell_quote "$SSH_PASS")"
  password_rssh "$vm" "printf '%s\n' $pass_q | sudo -S -p '' bash -lc $(shell_quote "$command")"
}
