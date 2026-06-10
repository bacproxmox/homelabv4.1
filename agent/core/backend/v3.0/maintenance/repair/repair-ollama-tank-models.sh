#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "repair-ollama-tank-models"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

VM="${OLLAMA_VMID:-106}"
TRUENAS_IP="${TRUENAS_IP:-192.168.50.101}"
OLLAMA_TANK_NFS="${OLLAMA_TANK_NFS:-${TRUENAS_IP}:/mnt/tank/ollama}"
OLLAMA_TANK_MOUNT="${OLLAMA_TANK_MOUNT:-/mnt/ollama}"
OLLAMA_LOCAL_ROOT="${OLLAMA_LOCAL_ROOT:-/opt/homelab/ollama}"

shell_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

echo "Repairing VM${VM} Ollama tank model mount."
echo "Expected NFS: ${OLLAMA_TANK_NFS}"
echo "VM mount: ${OLLAMA_TANK_MOUNT}"
echo "Ollama compose root: ${OLLAMA_LOCAL_ROOT}"

wait_ssh "$VM"

remote_cmd="sudo OLLAMA_TANK_NFS=$(shell_quote "$OLLAMA_TANK_NFS") OLLAMA_TANK_MOUNT=$(shell_quote "$OLLAMA_TANK_MOUNT") OLLAMA_LOCAL_ROOT=$(shell_quote "$OLLAMA_LOCAL_ROOT") bash -s"
rssh "$VM" "$remote_cmd" <<'REMOTE'
set -Eeuo pipefail

echo "VM side repair started."
echo "NFS source: ${OLLAMA_TANK_NFS}"
echo "Mount path: ${OLLAMA_TANK_MOUNT}"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker is not installed on VM106. Run OpenWebUI/Ollama service install first."
  exit 1
fi

if ! command -v mount.nfs >/dev/null 2>&1; then
  echo "Installing nfs-common."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-common
fi
if ! command -v rsync >/dev/null 2>&1; then
  echo "Installing rsync."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y rsync
fi

mkdir -p "$OLLAMA_TANK_MOUNT"
fstab_line="${OLLAMA_TANK_NFS} ${OLLAMA_TANK_MOUNT} nfs defaults,_netdev,x-systemd.automount,nofail 0 0"
if ! awk -v mp="$OLLAMA_TANK_MOUNT" '$2 == mp { found=1 } END { exit found ? 0 : 1 }' /etc/fstab; then
  echo "$fstab_line" >> /etc/fstab
fi

systemctl daemon-reload || true
mount "$OLLAMA_TANK_MOUNT" || mount -a || true

has_ollama_models() {
  local root="$1"
  [[ -d "$root/models" ]] || return 1
  find "$root/models" -mindepth 2 -maxdepth 4 2>/dev/null | grep -q .
}

find_existing_ollama_library() {
  for candidate in \
    /mnt/media/ollama \
    /mnt/media/Ollama \
    /mnt/media/ai/ollama \
    /mnt/media/models/ollama \
    /mnt/photos/ollama
  do
    if has_ollama_models "$candidate" || [[ -d "$candidate/manifests" ]]; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done
  return 1
}

if ! mountpoint -q "$OLLAMA_TANK_MOUNT"; then
  echo "Primary Ollama NFS mount failed. Checking common mounted tank paths for existing Ollama data."
  if found_library="$(find_existing_ollama_library)"; then
    OLLAMA_TANK_MOUNT="$found_library"
    echo "Using existing mounted Ollama library: $OLLAMA_TANK_MOUNT"
  fi
elif ! has_ollama_models "$OLLAMA_TANK_MOUNT"; then
  echo "Primary Ollama mount is available but no existing models were found there."
  if found_library="$(find_existing_ollama_library)"; then
    OLLAMA_TANK_MOUNT="$found_library"
    echo "Using existing mounted Ollama library instead: $OLLAMA_TANK_MOUNT"
  fi
fi

if [[ ! -d "$OLLAMA_TANK_MOUNT" ]]; then
  echo "ERROR: Ollama tank path is not available."
  echo "Expected TrueNAS export: ${OLLAMA_TANK_NFS}"
  echo "If your old model path is different, run with OLLAMA_TANK_NFS and OLLAMA_TANK_MOUNT overrides."
  if command -v showmount >/dev/null 2>&1; then
    server="${OLLAMA_TANK_NFS%%:*}"
    echo "TrueNAS NFS exports from $server:"
    showmount -e "$server" || true
  fi
  exit 1
fi

mkdir -p "$OLLAMA_TANK_MOUNT/models"
chown -R 1000:1000 "$OLLAMA_TANK_MOUNT" 2>/dev/null || true

LOCAL_OLLAMA_DIR="${OLLAMA_LOCAL_ROOT}/ollama"
LOCAL_MODELS="${LOCAL_OLLAMA_DIR}/models"
TARGET_MODELS="${OLLAMA_TANK_MOUNT}/models"
mkdir -p "$LOCAL_OLLAMA_DIR" "$TARGET_MODELS"

if [[ -d "$LOCAL_MODELS" && ! -L "$LOCAL_MODELS" ]]; then
  if find "$LOCAL_MODELS" -mindepth 1 -maxdepth 1 | grep -q .; then
    echo "Copying existing local Ollama models to tank with --ignore-existing."
    rsync -a --ignore-existing "${LOCAL_MODELS}/" "${TARGET_MODELS}/" || true
    backup="${LOCAL_MODELS}.local-backup-$(date +%Y%m%d-%H%M%S)"
    mv "$LOCAL_MODELS" "$backup"
    echo "Local model directory moved to: $backup"
  else
    rm -rf "$LOCAL_MODELS"
  fi
fi

cd "$OLLAMA_LOCAL_ROOT"
if [[ ! -f docker-compose.yml ]]; then
  echo "ERROR: ${OLLAMA_LOCAL_ROOT}/docker-compose.yml not found."
  echo "Run the OpenWebUI/Ollama install script first."
  exit 1
fi

cp docker-compose.yml "docker-compose.yml.bak-$(date +%Y%m%d-%H%M%S)"
python3 - "$OLLAMA_TANK_MOUNT" <<'PY'
from pathlib import Path
import re
import sys

mount = sys.argv[1].rstrip("/")
p = Path("docker-compose.yml")
s = p.read_text()
target = f"{mount}:/root/.ollama"

if target in s:
    print(f"Ollama compose volume already points to {target}")
    raise SystemExit(0)

pattern = r"(?m)^(\s*-\s*)[^#\n]*:/root/\.ollama\s*$"
s2, count = re.subn(pattern, rf"\g<1>{target}", s, count=1)
if count == 0:
    print("ERROR: Could not find an Ollama volume line ending with :/root/.ollama")
    raise SystemExit(1)

p.write_text(s2)
print(f"Ollama compose volume changed to {target}")
PY

echo "Recreating Ollama container."
docker network create homelab >/dev/null 2>&1 || true
docker compose up -d --force-recreate ollama
docker compose up -d open-webui || true

echo "Waiting for Ollama API."
for attempt in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo
echo "Ollama storage:"
df -h "$OLLAMA_TANK_MOUNT" || true
du -sh "$TARGET_MODELS" 2>/dev/null || true

echo
echo "Ollama model list:"
if ! docker exec hb-ollama ollama list; then
  echo "ERROR: Ollama container did not list models."
  docker logs hb-ollama --tail=120 || true
  exit 1
fi

echo
echo "Repair complete. Ollama now uses: ${OLLAMA_TANK_MOUNT}"
REMOTE

echo "VM${VM} Ollama tank model repair completed."
