#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/utils/logging.sh"
start_log "vm-110-pbs-backup"
source "$REPO_ROOT/lib/vm-cloudinit-common.sh"

PBS_VM_STORAGE="${PBS_VM_STORAGE:-nvme-vm}"
if ! pvesm status 2>/dev/null | awk '{print $1}' | grep -qx "$PBS_VM_STORAGE"; then
  echo "❌ VM110 için storage bulunamadı: $PBS_VM_STORAGE"
  exit 1
fi
VM_STORAGE="$PBS_VM_STORAGE"
VM110_RAM_MB="${VM110_RAM_MB:-4096}"
VM110_BALLOON_MB="${VM110_BALLOON_MB:-2048}"
VM110_ZRAM_MB="${VM110_ZRAM_MB:-1024}"
VM110_CORES="${VM110_CORES:-2}"
export VM110_BALLOON_MB VM110_ZRAM_MB

# PBS server packages are officially installed on Debian. Keep the known-good
# v2.4.1 cloud-init VM flow, only reducing OS disk size because datastore is external/NFS.
create_debian_vm 110 "pbs-backup" "192.168.50.110/24" "$VM110_RAM_MB" "$VM110_CORES" 64G "no" "none"

# Best-effort root password + SSH root login. The service installer repeats and validates it.
if [[ -f /root/homelab-secrets/users.env ]] && qm agent 110 ping >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source /root/homelab-secrets/users.env
  if [[ -n "${BACKUP_PASS:-}" ]]; then
    PASS_B64="$(printf '%s' "$BACKUP_PASS" | base64 -w0)"
    GUEST_SCRIPT="/tmp/homelab-pbs-root-ssh.sh"
    cat >/tmp/homelab-pbs-root-ssh.sh <<'GUEST'
#!/usr/bin/env bash
set -Eeuo pipefail
PASS="$(printf '%s' "$PASS_B64" | base64 -d)"
printf 'root:%s\n' "$PASS" | chpasswd
mkdir -p /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-homelab-root-login.conf <<'SSHCONF'
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
SSHCONF
systemctl restart ssh || systemctl restart sshd || true
GUEST
    qm guest exec 110 -- bash -lc "PASS_B64='$PASS_B64' bash -s" < /tmp/homelab-pbs-root-ssh.sh >/dev/null || echo "⚠️ VM110 root şifresi guest-agent ile set edilemedi; services/pbs install tekrar deneyecek."
    rm -f /tmp/homelab-pbs-root-ssh.sh
  fi
fi

echo "✅ VM110 hazır: pbs-backup"
echo "   Web UI service kurulumundan sonra: https://192.168.50.110:8007"
