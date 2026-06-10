#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/env-loader.sh"
source "$SCRIPT_DIR/../utils/logging.sh"
load_all_env

VM_STORAGE="${VM_STORAGE:-nvme-vm}"
BRIDGE="${BRIDGE:-vmbr0}"
GW="${LAN_GW:-192.168.50.1}"
DNS="${LAN_DNS:-1.1.1.1}"
IMG_URL="${IMG_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img}"
IMG_DIR="${IMG_DIR:-/var/lib/vz/template/iso}"
IMG="${IMG:-$IMG_DIR/ubuntu-noble-cloudimg-amd64.img}"
SNIPPET_DIR="${SNIPPET_DIR:-/var/lib/vz/snippets}"
FORCE_RECREATE="${FORCE_RECREATE:-0}"
AUTO_START="${AUTO_START:-1}"

mac_for_vmid() {
  local vmid="$1"
  local suffix
  suffix="$(printf '%02x' "$((vmid - 100))")"
  printf '02:23:14:00:01:%s' "$suffix"
}

prepare_host() {
  apt update
  apt install -y wget curl libguestfs-tools
  mkdir -p "$IMG_DIR" "$SNIPPET_DIR"
  pvesm set local --content iso,vztmpl,backup,snippets || true
  if [[ ! -f "$IMG" ]]; then
    wget -O "$IMG" "$IMG_URL"
  fi
}

ensure_root_ssh_key() {
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  if [[ ! -f /root/.ssh/id_ed25519 ]]; then
    echo "Proxmox root SSH key olusturuluyor; VM cloud-init authorized_keys icin gerekli."
    ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519 >/dev/null
  fi
  touch /root/.ssh/known_hosts
  chmod 600 /root/.ssh/known_hosts
}

wait_for_agent() {
  local vmid="$1" tries="${2:-60}"
  echo "⏳ VM $vmid qemu-guest-agent bekleniyor..."
  for _ in $(seq 1 "$tries"); do
    if qm agent "$vmid" ping >/dev/null 2>&1; then echo "✅ VM $vmid agent hazır"; return 0; fi
    sleep 5
  done
  echo "⚠️ Agent cevap vermedi; cloud-init devam ediyor olabilir."
  return 0
}

wait_for_agent() {
  local vmid="$1" tries="${2:-60}" ip="${3:-}" attempt
  echo "Waiting for VM $vmid qemu-guest-agent. SSH readiness is accepted as fallback."
  for attempt in $(seq 1 "$tries"); do
    if qm agent "$vmid" ping >/dev/null 2>&1; then
      echo "VM $vmid qemu-guest-agent is ready."
      return 0
    fi
    if [[ -n "$ip" ]] && timeout 3 bash -c ":</dev/tcp/$ip/22" >/dev/null 2>&1; then
      echo "VM $vmid SSH is reachable at $ip:22; continuing while qemu-guest-agent finishes in the background."
      return 0
    fi
    if (( attempt % 6 == 0 )); then
      echo "Still waiting for VM $vmid readiness, attempt $attempt/$tries."
    fi
    sleep 5
  done
  echo "Warning: VM $vmid qemu-guest-agent did not answer before timeout. Continuing; cloud-init may still be finishing."
  return 0
}

wait_for_vm_ssh_login() {
  local vmid="$1" ip="$2" tries="${3:-90}" attempt
  local ssh_user="${BACMASTER_USER:-bacmaster}" ssh_pass="${BACMASTER_PASS:-}"
  local base_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/root/.ssh/known_hosts -o ConnectTimeout=8)
  local key_opts=(-o BatchMode=yes "${base_opts[@]}")
  local pass_opts=(-o PreferredAuthentications=password -o PubkeyAuthentication=no "${base_opts[@]}")

  echo "VM $vmid SSH login bekleniyor: $ssh_user@$ip"
  for attempt in $(seq 1 "$tries"); do
    if ssh "${key_opts[@]}" "$ssh_user@$ip" 'echo ok' >/dev/null 2>/tmp/homelab-vm-ssh-key.err; then
      echo "VM $vmid SSH hazir: key auth"
      return 0
    fi
    if [[ -n "$ssh_pass" ]] && command -v sshpass >/dev/null 2>&1 \
      && sshpass -p "$ssh_pass" ssh "${pass_opts[@]}" "$ssh_user@$ip" 'echo ok' >/dev/null 2>/tmp/homelab-vm-ssh-pass.err; then
      echo "VM $vmid SSH hazir: password fallback"
      return 0
    fi
    if (( attempt % 12 == 0 )); then
      echo "Hala VM $vmid SSH login bekleniyor ($attempt/$tries)."
    fi
    sleep 5
  done

  echo "VM $vmid SSH login hazir olmadi: $ssh_user@$ip"
  echo "Key auth stderr:"
  sed -n '1,8p' /tmp/homelab-vm-ssh-key.err 2>/dev/null || true
  if [[ -n "$ssh_pass" ]] && command -v sshpass >/dev/null 2>&1; then
    echo "Password auth stderr:"
    sed -n '1,8p' /tmp/homelab-vm-ssh-pass.err 2>/dev/null || true
  else
    echo "Password fallback unavailable: sshpass missing or BACMASTER_PASS empty."
  fi
  return 1
}

create_cloudinit_snippet() {
  local vmid="$1" vmname="$2" install_docker="$3" mount_profile="$4" snippet="$SNIPPET_DIR/vm${vmid}-${vmname}-user.yaml"
  local root_pub="" zram_var zram_mb
  zram_var="VM${vmid}_ZRAM_MB"
  zram_mb="${!zram_var:-0}"
  ensure_root_ssh_key
  [[ -f /root/.ssh/id_ed25519.pub ]] && root_pub="$(cat /root/.ssh/id_ed25519.pub)"

  cat > "$snippet" <<CLOUDINIT
#cloud-config
hostname: ${vmname}
manage_etc_hosts: true

users:
  - name: ${BACMASTER_USER}
    uid: ${BACMASTER_UID}
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    ssh_authorized_keys:
      - ${root_pub}
  - name: ${MEDIA_USER}
    uid: ${MEDIA_UID}
    shell: /usr/sbin/nologin
    lock_passwd: true

chpasswd:
  expire: false
  list: |
    ${BACMASTER_USER}:${BACMASTER_PASS}

ssh_pwauth: true
disable_root: true
package_update: true
package_upgrade: false
packages:
  - sudo
  - qemu-guest-agent
  - curl
  - wget
  - nano
  - git
  - ca-certificates
  - gnupg
  - lsb-release
  - net-tools
  - nfs-common
  - cifs-utils
  - htop
  - unzip
  - jq
  - rsync
  - util-linux
runcmd:
  - systemctl enable --now qemu-guest-agent
  - groupadd -f docker
  - groupadd -f video
  - groupadd -f render
  - usermod -aG docker,video,render ${BACMASTER_USER}
  - mkdir -p /mnt/media /mnt/photos /mnt/private-photos /mnt/private-documents /mnt/ollama /opt/homelab
CLOUDINIT

  if [[ "$mount_profile" == *"media"* ]]; then
    echo '  - grep -q "/mnt/media " /etc/fstab || echo "192.168.50.101:/mnt/tank/media /mnt/media nfs defaults,_netdev,x-systemd.automount 0 0" >> /etc/fstab' >> "$snippet"
  fi
  if [[ "$mount_profile" == *"tankphotos"* ]]; then
    echo '  - grep -q "/mnt/photos " /etc/fstab || echo "192.168.50.101:/mnt/tank/photos /mnt/photos nfs defaults,_netdev,x-systemd.automount 0 0" >> /etc/fstab' >> "$snippet"
  fi
  if [[ "$mount_profile" == *"privatephotos"* ]]; then
    echo '  - grep -q "/mnt/private-photos " /etc/fstab || echo "192.168.50.101:/mnt/tank/private/photos /mnt/private-photos nfs defaults,_netdev,x-systemd.automount 0 0" >> /etc/fstab' >> "$snippet"
  fi
  if [[ "$mount_profile" == *"privatedocuments"* ]]; then
    echo '  - grep -q "/mnt/private-documents " /etc/fstab || echo "192.168.50.101:/mnt/tank/private/documents /mnt/private-documents nfs defaults,_netdev,x-systemd.automount 0 0" >> /etc/fstab' >> "$snippet"
  fi
  if [[ "$mount_profile" == *"ollama"* ]]; then
    echo '  - grep -q "/mnt/ollama " /etc/fstab || echo "192.168.50.101:/mnt/tank/ollama /mnt/ollama nfs defaults,_netdev,x-systemd.automount,nofail 0 0" >> /etc/fstab' >> "$snippet"
  fi

  cat >> "$snippet" <<CLOUDINIT
  - systemctl daemon-reload
  - mount -a || true
CLOUDINIT

  if [[ "$install_docker" == "yes" ]]; then
    cat >> "$snippet" <<CLOUDINIT
  - curl -fsSL https://get.docker.com | sh
  - usermod -aG docker ${BACMASTER_USER}
  - systemctl enable --now docker
  - docker network create homelab || true
CLOUDINIT
  fi

  if [[ "$zram_mb" =~ ^[0-9]+$ && "$zram_mb" -gt 0 ]]; then
    cat >> "$snippet" <<CLOUDINIT
  - printf 'vm.swappiness=10\n' >/etc/sysctl.d/90-homelab-memory.conf
  - sysctl --system || true
  - |
    cat >/etc/systemd/system/homelab-zram-swap.service <<'SERVICE'
    [Unit]
    Description=Homelab zram swap
    After=multi-user.target

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/bin/bash -lc 'if swapon --show=NAME --noheadings | grep -q "^/dev/zram"; then exit 0; fi; modprobe zram || true; dev="\$(zramctl -f --algorithm zstd --size ${zram_mb}M 2>/dev/null || zramctl -f --algorithm lz4 --size ${zram_mb}M 2>/dev/null || zramctl -f --size ${zram_mb}M)"; mkswap "\$dev"; swapon -p 100 "\$dev"'
    ExecStop=/bin/bash -lc 'for dev in \$(swapon --show=NAME --noheadings | grep "^/dev/zram" || true); do swapoff "\$dev" || true; zramctl -r "\$dev" || true; done'

    [Install]
    WantedBy=multi-user.target
    SERVICE
    systemctl daemon-reload
    systemctl enable --now homelab-zram-swap.service || true
CLOUDINIT
  fi

  cat >> "$snippet" <<CLOUDINIT
  - systemctl restart ssh
final_message: "VM ${vmname} cloud-init finished."
CLOUDINIT
  echo "$snippet"
}

create_ubuntu_vm() {
  local vmid="$1" vmname="$2" ip_cidr="$3" ram="$4" cores="$5" disk_size="$6" install_docker="${7:-yes}" mount_profile="${8:-none}"
  local balloon_var balloon
  require_root
  prepare_host
  if qm status "$vmid" &>/dev/null; then
    if [[ "$FORCE_RECREATE" == "1" ]]; then
      qm stop "$vmid" 2>/dev/null || true
      qm destroy "$vmid" --purge 2>/dev/null || true
    else
      echo "✅ VM $vmid zaten var. FORCE_RECREATE=1 bash $0 ile yeniden oluşturabilirsin."
      return 0
    fi
  fi
  local snippet; snippet="$(create_cloudinit_snippet "$vmid" "$vmname" "$install_docker" "$mount_profile")"
  local vm_mac vm_mac_var
  vm_mac_var="VM${vmid}_MAC"
  vm_mac="${!vm_mac_var:-$(mac_for_vmid "$vmid")}"
  balloon_var="VM${vmid}_BALLOON_MB"
  balloon="${!balloon_var:-0}"
  [[ "$balloon" =~ ^[0-9]+$ ]] || balloon=0
  echo "🖥️ VM oluşturuluyor: $vmid / $vmname / $ip_cidr / RAM $ram / CPU $cores / Disk $disk_size / MAC $vm_mac"
  qm create "$vmid" --name "$vmname" --memory "$ram" --cores "$cores" --cpu host --machine q35 --bios ovmf --net0 "virtio=${vm_mac},bridge=${BRIDGE}" --ostype l26 --agent enabled=1 --scsihw virtio-scsi-single --serial0 socket --vga none --tablet 0 --onboot 1 --balloon "$balloon"
  qm importdisk "$vmid" "$IMG" "$VM_STORAGE"
  qm set "$vmid" --scsi0 "$VM_STORAGE:vm-${vmid}-disk-0,iothread=1,discard=on,ssd=1" --efidisk0 "$VM_STORAGE:1,efitype=4m,pre-enrolled-keys=0" --ide2 "$VM_STORAGE:cloudinit" --boot order=scsi0
  qm resize "$vmid" scsi0 "$disk_size"
  qm set "$vmid" --cicustom "user=local:snippets/$(basename "$snippet")" --ipconfig0 "ip=${ip_cidr},gw=${GW}" --nameserver "$DNS" --ciupgrade 0
  qm cloudinit update "$vmid"
  if [[ "$AUTO_START" == "1" ]]; then
    qm start "$vmid"
    wait_for_agent "$vmid" 60 "${ip_cidr%/*}"
    wait_for_vm_ssh_login "$vmid" "${ip_cidr%/*}" "${HOMELAB_VM_SSH_WAIT_TRIES:-90}"
  fi
  echo "✅ VM hazır: $vmname - ssh ${BACMASTER_USER}@${ip_cidr%/*}"
}

create_debian_vm() {
  # Proxmox Backup Server is officially installed on Debian packages/repos, not Ubuntu.
  # This wrapper keeps the same cloud-init VM creation flow while switching the base image.
  local old_img_url="${IMG_URL:-}" old_img="${IMG:-}"
  IMG_URL="${DEBIAN_IMG_URL:-https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2}"
  IMG="${DEBIAN_IMG:-$IMG_DIR/debian-13-genericcloud-amd64.qcow2}"
  create_ubuntu_vm "$@"
  IMG_URL="$old_img_url"
  IMG="$old_img"
}

find_pci_by_regex() { lspci -Dnn | grep -Ei "$1" | awk '{print $1}' | head -n1 || true; }
find_all_pci_by_regex() { lspci -Dnn | grep -Ei "$1" | awk '{print $1}' || true; }
pci_short() { echo "$1" | sed 's/^0000://'; }
