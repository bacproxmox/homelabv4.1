#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${HOMELABV4_ROOT:-/opt/homelabv4}"
AGENT="$ROOT/agent"

load_vm_ssh_env() {
  local env_file
  for env_file in \
    /root/homelab-secrets/global.env \
    /root/homelab-secrets/users.env \
    /root/homelab-secrets/truenas-login.env
  do
    if [[ -f "$env_file" ]]; then
      set +u
      # shellcheck disable=SC1090
      source "$env_file" || true
      set -u
    fi
  done

  export HOMELAB_ADMIN_USER="${HOMELAB_ADMIN_USER:-${BACMASTER_USER:-bacmaster}}"
  export HOMELAB_ADMIN_PASS="${HOMELAB_ADMIN_PASS:-${BACMASTER_PASS:-${SSH_PASS:-}}}"
  export NEXTCLOUD_SSH_USER="${NEXTCLOUD_SSH_USER:-$HOMELAB_ADMIN_USER}"
  export NEXTCLOUD_SSH_PASS="${NEXTCLOUD_SSH_PASS:-$HOMELAB_ADMIN_PASS}"
  export JELLYFIN_SSH_USER="${JELLYFIN_SSH_USER:-$HOMELAB_ADMIN_USER}"
  export JELLYFIN_SSH_PASS="${JELLYFIN_SSH_PASS:-$HOMELAB_ADMIN_PASS}"
}

prepare_vm_ssh_client() {
  local ip
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  for ip in 192.168.50.101 192.168.50.102 192.168.50.103 192.168.50.104 192.168.50.105 192.168.50.106 192.168.50.107 192.168.50.110; do
    ssh-keygen -R "$ip" -f /root/.ssh/known_hosts >/dev/null 2>&1 || true
  done

  if [[ -n "${HOMELAB_ADMIN_PASS:-}${NEXTCLOUD_SSH_PASS:-}${JELLYFIN_SSH_PASS:-}" ]] && ! command -v sshpass >/dev/null 2>&1; then
    echo "sshpass missing; installing for password-based VM branding SSH."
    DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y sshpass >/dev/null 2>&1 || true
  fi
}

run_vendor() {
  local script="$1"
  local mode="$2"
  if [[ ! -f "$script" ]]; then
    echo "Vendor branding script missing: $script"
    echo "The pack is registered but its vendor payload was not uploaded."
    exit 4
  fi
  chmod +x "$script"
  load_vm_ssh_env
  prepare_vm_ssh_client
  exec bash "$script" "$mode"
}
