#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "repair-chia-plot-disks"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

wait_ssh 107
NO_START="${HOMELAB_CHIA_NO_START:-0}"
EXPECTED_REMOTE="${EXPECTED_CHIA_PLOT_DISKS:-5}"
rssh 107 "sudo EXPECTED_CHIA_PLOT_DISKS='$EXPECTED_REMOTE' HOMELAB_CHIA_NO_START='$NO_START' bash -s" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
CHIA_BIN="/opt/chia-blockchain/venv/bin/chia"
CONFIG="/home/bacmaster/.chia/mainnet/config/config.yaml"
PLOT_ROOT="/mnt/chia-plots"
EXPECTED="${EXPECTED_CHIA_PLOT_DISKS:-5}"
NO_START="${HOMELAB_CHIA_NO_START:-0}"

mkdir -p "$PLOT_ROOT"

mapfile -t PARTS < <(find /dev/disk/by-id -maxdepth 1 -type l \
  | grep -E 'ata-TOSHIBA_HDWG(180|480).*part1$' \
  | grep -Ev 'MG10|ST4000|EXCERIA|KIOXIA' \
  | sort -u)

count="${#PARTS[@]}"
echo "💽 Chia plot partition sayısı: $count / beklenen $EXPECTED"
printf '  %s\n' "${PARTS[@]}"
if [[ "$count" -lt "$EXPECTED" ]]; then
  echo "⚠️ Beklenen plot disk sayısından az görünüyor. Eksik disk için Proxmox/JMicron/power/cable kontrol et."
fi

cp /etc/fstab "/etc/fstab.bak-chia-plots-$(date +%Y%m%d-%H%M%S)"
idx=1
for part in "${PARTS[@]}"; do
  [[ "$idx" -le "$EXPECTED" ]] || break
  mp="$PLOT_ROOT/disk$idx"
  mkdir -p "$mp"
  if ! grep -Fq "$part " /etc/fstab; then
    echo "$part $mp auto defaults,nofail,x-systemd.device-timeout=10 0 2" >> /etc/fstab
  fi
  idx=$((idx+1))
done

systemctl daemon-reload
mount -a || true

echo "📦 Mount durumu:"
df -h | grep "$PLOT_ROOT" || true
mounted_count="$(findmnt -rn -o TARGET | grep -E "^${PLOT_ROOT}/disk[0-9]+$" | sort -V | wc -l)"
echo "🔢 Mounted plot disk sayısı: ${mounted_count} / beklenen ${EXPECTED}"
if [[ "$mounted_count" -lt "$EXPECTED" ]]; then
  echo "⚠️ Mount edilen plot disk sayısı beklenenden az. Chia çalışır ama eksik disklerle farm yapar."
fi

for mp in "$PLOT_ROOT"/disk*; do
  [[ -d "$mp" ]] || continue
  chmod 755 "$mp" 2>/dev/null || true
  find "$mp" -maxdepth 1 -type f -name '*.plot' -exec chmod 644 {} \; 2>/dev/null || true
  find "$mp" -maxdepth 1 -type f -name '*.plot' -exec chown bacmaster:bacmaster {} \; 2>/dev/null || true
  echo "✅ Readable check: $mp"
  sudo -u bacmaster test -r "$mp" && echo "   ok" || echo "   ⚠️ bacmaster okuyamıyor"
done

if [[ -x "$CHIA_BIN" ]]; then
  ln -sf "$CHIA_BIN" /usr/local/bin/chia
  echo "✅ chia symlink hazır: /usr/local/bin/chia -> $CHIA_BIN"
else
  echo "⚠️ Chia binary bulunamadı: $CHIA_BIN"
fi

if [[ -f "$CONFIG" ]]; then
  cp "$CONFIG" "$CONFIG.bak-decompressor-$(date +%Y%m%d-%H%M%S)"
  sudo -u bacmaster python3 - <<'PY'
from pathlib import Path
p=Path.home()/'.chia/mainnet/config/config.yaml'
text=p.read_text()
lines=text.splitlines()
out=[]
seen_harvester=False
inserted=False
for line in lines:
    if line.startswith('harvester:'):
        seen_harvester=True
        out.append(line)
        continue
    if seen_harvester and line and not line.startswith(' '):
        if not inserted:
            out.append('  parallel_decompressor_count: 1')
            inserted=True
        seen_harvester=False
    if line.strip().startswith('parallel_decompressor_count:'):
        indent=line[:len(line)-len(line.lstrip())]
        out.append(f'{indent}parallel_decompressor_count: 1')
        inserted=True
    else:
        out.append(line)
if not inserted:
    if not any(l.startswith('harvester:') for l in out):
        out.extend(['harvester:', '  parallel_decompressor_count: 1'])
    else:
        new=[]
        done=False
        for l in out:
            new.append(l)
            if l.startswith('harvester:') and not done:
                new.append('  parallel_decompressor_count: 1')
                done=True
        out=new
p.write_text('\n'.join(out)+'\n')
print('✅ parallel_decompressor_count: 1')
PY
fi

if [[ -x "$CHIA_BIN" ]]; then
  for mp in "$PLOT_ROOT"/disk*; do
    [[ -d "$mp" ]] || continue
    if sudo -u bacmaster test -r "$mp"; then
      sudo -u bacmaster "$CHIA_BIN" plots add -d "$mp" || true
    else
      echo "⚠️ Chia path eklenmedi, readable değil: $mp"
    fi
  done
  if [[ "$NO_START" == "1" ]]; then
    echo "Chia start skipped by Homelabv4 deferred DB mode."
    sudo -u bacmaster "$CHIA_BIN" stop all -d >/dev/null 2>&1 || true
    systemctl disable --now chia-farmer.service >/dev/null 2>&1 || true
  else
    sudo -u bacmaster "$CHIA_BIN" start farmer -r || true
    sleep 5
  fi
  echo "📋 Chia plot dirs:"
  sudo -u bacmaster "$CHIA_BIN" plots show || true
  if [[ "$NO_START" != "1" ]]; then
  echo "🌱 Chia farm summary:"
  sudo -u bacmaster "$CHIA_BIN" farm summary || true
  echo "🔌 Chia daemon port 55400:"
  ss -ltnp | grep 55400 || true
  fi
fi

echo "🔢 Plot file count:"
find "$PLOT_ROOT"/disk* -maxdepth 1 -type f -name '*.plot' 2>/dev/null | wc -l
REMOTE
