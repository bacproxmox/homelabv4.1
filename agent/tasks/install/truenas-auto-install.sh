#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${HOMELABV4_ROOT:-/opt/homelabv4}"
AGENT="${HOMELABV4_AGENT:-$ROOT/agent}"
STATE="${HOMELABV4_STATE:-$ROOT/state}"
PROFILE="$STATE/install-profile.json"
SECRETS="/root/homelab-secrets/truenas-login.env"

VMID="${TRUENAS_VMID:-101}"
VM_NAME="${TRUENAS_VM_NAME:-truenas}"
VM_STORAGE="${VM_STORAGE:-nvme-vm}"
BOOT_DISK_GB="${TRUENAS_OS_DISK:-64}"
RAM_MB="${TRUENAS_RAM_MB:-${TRUENAS_VM_RAM:-16384}}"
CORES="${TRUENAS_CORES:-4}"
TRUENAS_MAC="${TRUENAS_MAC:-02:23:14:00:01:01}"
TRUENAS_IP_DEFAULT="192.168.50.101"
TRUENAS_USER_DEFAULT="truenas_admin"
TRUENAS_PRIVATE_REQUIRED="${TRUENAS_PRIVATE_REQUIRED:-0}"

manual_fallback() {
  local reason="$1"
  echo "MANUAL_CHECKPOINT_REQUIRED"
  echo "Reason: $reason"
  cat <<'EOF'
Manual recovery steps:
1. Open Proxmox VM101 Console.
2. Finish the Bacmasters-NAS / TrueNAS installer manually.
3. Make sure SSH is enabled and truenas_admin uses the password saved in Homelabv4.
4. On Proxmox, run: qm set 101 --delete ide2; qm set 101 --boot order=scsi0; qm start 101
5. Return to Homelabv4 and run the TrueNAS guided step again.
EOF
  exit 2
}

private_required() {
  case "${TRUENAS_PRIVATE_REQUIRED:-0}" in
    1|true|True|TRUE|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || manual_fallback "Required command is missing on Proxmox: $1"
}

json_value() {
  local path="$1"
  python3 - "$PROFILE" "$path" <<'PY'
import json
import sys
profile, path = sys.argv[1], sys.argv[2]
try:
    with open(profile, "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    print("")
    raise SystemExit(0)
cur = data
for part in path.split("."):
    if isinstance(cur, dict):
        cur = cur.get(part, "")
    else:
        cur = ""
if cur is None:
    cur = ""
print(cur if isinstance(cur, str) else json.dumps(cur))
PY
}

find_disk_by_id() {
  local candidate
  shopt -s nullglob
  for candidate in "$@"; do
    for path in /dev/disk/by-id/$candidate; do
      [[ -e "$path" ]] || continue
      [[ "$path" == *-part* ]] && continue
      printf '%s\n' "$path"
      return 0
    done
  done
  return 1
}

by_id_for_block() {
  local block="$1" path resolved
  shopt -s nullglob
  for path in /dev/disk/by-id/ata-* /dev/disk/by-id/scsi-* /dev/disk/by-id/wwn-* /dev/disk/by-id/*; do
    [[ -e "$path" ]] || continue
    [[ "$path" == *-part* ]] && continue
    resolved="$(readlink -f "$path" 2>/dev/null || true)"
    if [[ "$resolved" == "/dev/$block" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  printf '/dev/%s\n' "$block"
}

find_single_disk_by_size_model() {
  local min_bytes="$1" max_bytes="$2" model_regex="$3"
  local sys block model vendor serial size_sectors size_bytes text path
  local -a size_matches=()

  for sys in /sys/block/*; do
    [[ -d "$sys" ]] || continue
    block="$(basename "$sys")"
    case "$block" in
      nvme*|loop*|ram*|sr*|zd*)
        continue
        ;;
    esac
    [[ -f "$sys/size" ]] || continue
    size_sectors="$(cat "$sys/size" 2>/dev/null || echo 0)"
    [[ "$size_sectors" =~ ^[0-9]+$ ]] || continue
    size_bytes=$(( size_sectors * 512 ))
    (( size_bytes >= min_bytes && size_bytes <= max_bytes )) || continue

    model="$(cat "$sys/device/model" 2>/dev/null || true)"
    vendor="$(cat "$sys/device/vendor" 2>/dev/null || true)"
    serial="$(cat "$sys/device/serial" 2>/dev/null || true)"
    text="$vendor $model $serial $block"
    path="$(by_id_for_block "$block")"

    if [[ "$text" =~ $model_regex ]]; then
      printf '%s\n' "$path"
      return 0
    fi
    size_matches+=("$path")
  done

  if [[ "${#size_matches[@]}" -eq 1 ]]; then
    printf '%s\n' "${size_matches[0]}"
    return 0
  fi
  return 1
}

print_disk_candidates() {
  echo
  echo "Visible non-NVMe disk candidates:"
  lsblk -dn -o NAME,SIZE,MODEL,SERIAL,TRAN,TYPE 2>/dev/null | awk '$1 !~ /^nvme/ && $6 == "disk" {print "  " $0}' || true
  echo
  echo "Relevant /dev/disk/by-id entries:"
  find /dev/disk/by-id -maxdepth 1 -type l 2>/dev/null \
    | grep -Eiv -- '-part[0-9]+$' \
    | grep -Ei 'TOSHIBA|MG10|ST4000|SkyHawk|Seagate|wwn|ata-|scsi-' \
    | sort \
    | sed 's#^#  #' || true
  echo
}

assert_not_nvme_passthrough() {
  local disk="$1" label="$2" resolved
  resolved="$(readlink -f "$disk" 2>/dev/null || true)"
  [[ -n "$resolved" ]] || manual_fallback "$label disk path does not resolve: $disk"
  case "$resolved" in
    /dev/nvme*)
      manual_fallback "$label disk resolves to NVMe ($resolved); NVMe passthrough to TrueNAS is blocked."
      ;;
  esac
}

ensure_sshpass() {
  if command -v sshpass >/dev/null 2>&1; then
    return
  fi
  echo "sshpass is missing; installing it for noninteractive TrueNAS SSH verification."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y sshpass
}

storage_exists() {
  pvesm status 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx "$VM_STORAGE"
}

stop_vm_if_running() {
  if ! qm status "$VMID" >/dev/null 2>&1; then
    return
  fi
  local status
  status="$(qm status "$VMID" | awk '{print $2}')"
  if [[ "$status" != "running" ]]; then
    return
  fi
  echo "VM$VMID is running; requesting shutdown before reconfiguring the installer boot."
  qm shutdown "$VMID" --timeout 60 || true
  status="$(qm status "$VMID" | awk '{print $2}')"
  if [[ "$status" == "running" ]]; then
    echo "VM$VMID did not stop cleanly; stopping it for the auto-install flow."
    qm stop "$VMID"
  fi
}

ensure_vm() {
  if qm status "$VMID" >/dev/null 2>&1; then
    echo "Updating existing VM$VMID ($VM_NAME)."
  else
    echo "Creating VM$VMID ($VM_NAME)."
    qm create "$VMID" \
      --name "$VM_NAME" \
      --memory "$RAM_MB" \
      --cores "$CORES" \
      --cpu host \
      --machine q35 \
      --bios ovmf \
      --scsihw virtio-scsi-single \
      --net0 "virtio=$TRUENAS_MAC,bridge=vmbr0" \
      --onboot 1 \
      --balloon 0 \
      --vga vmware \
      --agent 1
  fi

  qm set "$VMID" \
    --name "$VM_NAME" \
    --memory "$RAM_MB" \
    --cores "$CORES" \
    --cpu host \
    --machine q35 \
    --bios ovmf \
    --scsihw virtio-scsi-single \
    --net0 "virtio=$TRUENAS_MAC,bridge=vmbr0" \
    --onboot 1 \
    --balloon 0 \
    --vga vmware \
    --agent 1

  if ! qm config "$VMID" | grep -q '^efidisk0:'; then
    qm set "$VMID" --efidisk0 "$VM_STORAGE:1,format=raw,efitype=4m"
  fi
  if ! qm config "$VMID" | grep -q '^scsi0:'; then
    qm set "$VMID" --scsi0 "$VM_STORAGE:${BOOT_DISK_GB},discard=on,ssd=1,iothread=1"
  fi
}

ssh_true_nas() {
  sshpass -p "$TRUENAS_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=8 \
    "$TRUENAS_USER@$TRUENAS_IP" "$@"
}

vm_power_state() {
  qm status "$VMID" 2>/dev/null | awk '{print $2}'
}

wait_for_installer_completion() {
  local attempts="${1:-180}" delay="${2:-20}" attempt status
  echo "Waiting for TrueNAS installer completion: VM shutdown or SSH at $TRUENAS_IP:22."
  for attempt in $(seq 1 "$attempts"); do
    status="$(vm_power_state || true)"
    if [[ "$status" != "running" ]]; then
      echo "TrueNAS installer VM is no longer running (status: ${status:-unknown}). Treating this as completed auto-install."
      return 0
    fi
    if ssh_true_nas 'hostname >/dev/null; true' >/dev/null 2>&1; then
      echo "TrueNAS SSH became ready before installer shutdown. Continuing with disk boot switch."
      return 0
    fi
    if (( attempt % 6 == 0 )); then
      echo "Still waiting for installer completion, attempt $attempt/$attempts. VM status: ${status:-unknown}."
    fi
    sleep "$delay"
  done
  manual_fallback "TrueNAS installer did not shut down and SSH did not become reachable."
}

switch_to_disk_boot() {
  local status
  echo "Switching VM$VMID boot order to the installed boot disk."
  qm set "$VMID" --delete ide2 || qm set "$VMID" --ide2 none || true
  qm set "$VMID" --boot order=scsi0
  status="$(vm_power_state || true)"
  if [[ "$status" == "running" ]]; then
    qm reboot "$VMID" || qm reset "$VMID" || true
  else
    qm start "$VMID"
  fi
}

wait_for_truenas_ssh() {
  local label="$1" attempts="${2:-180}" delay="${3:-20}" attempt
  echo "Waiting for TrueNAS SSH ($label) at $TRUENAS_IP:22."
  for attempt in $(seq 1 "$attempts"); do
    if ssh_true_nas 'hostname >/dev/null; true' >/dev/null 2>&1; then
      echo "TrueNAS SSH is ready ($label)."
      return 0
    fi
    if (( attempt % 6 == 0 )); then
      echo "Still waiting for TrueNAS SSH ($label), attempt $attempt/$attempts."
    fi
    sleep "$delay"
  done
  manual_fallback "TrueNAS SSH did not become reachable during $label."
}

ensure_login_env_compat() {
  mkdir -p "$(dirname "$SECRETS")"
  touch "$SECRETS"
  chmod 600 "$SECRETS" 2>/dev/null || true
  grep -q '^TRUENAS_SSH_PASS=' "$SECRETS" || printf 'TRUENAS_SSH_PASS=%q\n' "$TRUENAS_PASS" >> "$SECRETS"
  grep -q '^TRUENAS_PASS=' "$SECRETS" || printf 'TRUENAS_PASS=%q\n' "$TRUENAS_PASS" >> "$SECRETS"
  grep -q '^TRUENAS_ADMIN_PASSWORD=' "$SECRETS" || printf 'TRUENAS_ADMIN_PASSWORD=%q\n' "$TRUENAS_PASS" >> "$SECRETS"
  grep -q '^TRUENAS_HOST=' "$SECRETS" || printf 'TRUENAS_HOST=%q\n' "$TRUENAS_IP" >> "$SECRETS"
  grep -q '^TRUENAS_FINAL_IP=' "$SECRETS" || printf 'TRUENAS_FINAL_IP=%q\n' "$TRUENAS_IP" >> "$SECRETS"
}

run_truenas_postinstall_storage() {
  local flow="$AGENT/core/flows/truenas/postinstall-and-storage.sh"
  [[ -f "$flow" ]] || manual_fallback "TrueNAS post-install/storage flow is missing: $flow"
  echo "Running TrueNAS post-install: pool import, API key, users, datasets, NFS and SMB."
  HOMELAB_ROOT="$AGENT/core" \
  TRUENAS_SSH_READY_ASSUMED=1 \
  TRUENAS_SKIP_BOOT_FIX=1 \
  TRUENAS_PRIVATE_REQUIRED="${TRUENAS_PRIVATE_REQUIRED:-0}" \
  TRUENAS_HOST="$TRUENAS_IP" \
  TRUENAS_FINAL_IP="$TRUENAS_IP" \
  bash "$flow"
}

echo "Homelabv4 TrueNAS auto install"
echo "Target: VM$VMID $VM_NAME, IP $TRUENAS_IP_DEFAULT, MAC $TRUENAS_MAC"

need_cmd python3
need_cmd qm
need_cmd pvesm
need_cmd sha256sum
need_cmd awk

[[ -f "$PROFILE" ]] || manual_fallback "TrueNAS ISO metadata is missing. Upload Bacmasters-NAS_*.iso from the Windows panel first."

ISO_FILE="$(json_value 'truenasIso.fileName')"
EXPECTED_SHA="$(json_value 'truenasIso.sha256')"
[[ -n "$ISO_FILE" ]] || manual_fallback "TrueNAS ISO fileName is missing from $PROFILE."
[[ "$ISO_FILE" == *.iso ]] || manual_fallback "Selected TrueNAS media is not an ISO: $ISO_FILE"

REMOTE_ISO="/var/lib/vz/template/iso/$ISO_FILE"
[[ -f "$REMOTE_ISO" ]] || manual_fallback "Uploaded ISO is missing on Proxmox: $REMOTE_ISO"
REMOTE_SHA="$(sha256sum "$REMOTE_ISO" | awk '{print $1}')"
if [[ -n "$EXPECTED_SHA" && "${REMOTE_SHA,,}" != "${EXPECTED_SHA,,}" ]]; then
  manual_fallback "Uploaded ISO SHA256 mismatch. Expected $EXPECTED_SHA, got $REMOTE_SHA."
fi

source "$SECRETS" 2>/dev/null || true
TRUENAS_IP="${TRUENAS_IP:-$TRUENAS_IP_DEFAULT}"
TRUENAS_USER="${TRUENAS_SSH_USER:-$TRUENAS_USER_DEFAULT}"
TRUENAS_PASS="${TRUENAS_SSH_PASS:-${TRUENAS_PASS:-${TRUENAS_ADMIN_PASSWORD:-}}}"
[[ -n "$TRUENAS_PASS" ]] || manual_fallback "TrueNAS admin password is missing in $SECRETS."
export TRUENAS_SSH_PASS="$TRUENAS_PASS" TRUENAS_PASS TRUENAS_ADMIN_PASSWORD="$TRUENAS_PASS"
ensure_login_env_compat

storage_exists || manual_fallback "Proxmox storage '$VM_STORAGE' is not available."

TANK_DISK="${TRUENAS_TANK_DISK:-}"
if [[ -z "$TANK_DISK" ]]; then
  TANK_DISK="$(find_disk_by_id 'ata-TOSHIBA_MG10ACA20TE*' 'ata-*MG10ACA20TE*' || true)"
fi
if [[ -z "$TANK_DISK" ]]; then
  TANK_DISK="$(find_single_disk_by_size_model 18000000000000 22000000000000 'TOSHIBA|MG10|20TE' || true)"
fi
if [[ -z "$TANK_DISK" ]]; then
  print_disk_candidates
  manual_fallback "20TB Toshiba MG10 tank disk not found. Set TRUENAS_TANK_DISK and rerun."
fi

PRIVATE_DISK="${TRUENAS_PRIVATE_DISK:-}"
if private_required; then
  if [[ -z "$PRIVATE_DISK" ]]; then
    PRIVATE_DISK="$(find_disk_by_id 'ata-ST4000VX007*' 'ata-*ST4000VX007*' 'ata-Seagate_SkyHawk*' || true)"
  fi
  if [[ -z "$PRIVATE_DISK" ]]; then
    PRIVATE_DISK="$(find_single_disk_by_size_model 3500000000000 4500000000000 'Seagate|ST4000VX007|SkyHawk' || true)"
  fi
  if [[ -z "$PRIVATE_DISK" ]]; then
    print_disk_candidates
    manual_fallback "TRUENAS_PRIVATE_REQUIRED=1 but the 4TB private disk was not found. Set TRUENAS_PRIVATE_DISK or rerun with TRUENAS_PRIVATE_REQUIRED=0."
  fi
else
  echo "TRUENAS_PRIVATE_REQUIRED=0; 4TB private passthrough is optional and will be skipped."
  echo "Private datasets and shares will be created under /mnt/tank/private."
fi

assert_not_nvme_passthrough "$TANK_DISK" "tank"
if private_required; then
  assert_not_nvme_passthrough "$PRIVATE_DISK" "private"
fi

ensure_sshpass
stop_vm_if_running
ensure_vm

echo "Attaching TrueNAS install ISO and storage passthrough disks."
qm set "$VMID" --ide2 "local:iso/$ISO_FILE,media=cdrom"
qm set "$VMID" --scsi1 "$TANK_DISK,serial=TANK20TB"
if private_required; then
  qm set "$VMID" --scsi2 "$PRIVATE_DISK,serial=PRIVATE4TB"
else
  qm set "$VMID" --delete scsi2 >/dev/null 2>&1 || true
fi
qm set "$VMID" --boot order=ide2

echo "Starting VM$VMID from $ISO_FILE."
qm start "$VMID"
wait_for_installer_completion "${TRUENAS_AUTO_INSTALL_ATTEMPTS:-180}" "${TRUENAS_AUTO_INSTALL_DELAY:-20}"
switch_to_disk_boot
wait_for_truenas_ssh "post-install disk boot" "${TRUENAS_REBOOT_SSH_ATTEMPTS:-60}" "${TRUENAS_REBOOT_SSH_DELAY:-15}"
run_truenas_postinstall_storage

echo "Running Bacmaster's NAS branding status check."
if [[ -x "$AGENT/tasks/branding/bacmasters-nas-truenas-status.sh" ]]; then
  bash "$AGENT/tasks/branding/bacmasters-nas-truenas-status.sh" || echo "Branding status check returned non-zero; review the log and reapply from the Branding tab if needed."
else
  echo "Branding status task is missing; skipping status check."
fi

echo "TrueNAS VM101 auto install flow completed."
