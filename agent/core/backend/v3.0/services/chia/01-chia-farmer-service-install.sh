#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/utils/env-loader.sh"
source "$REPO_ROOT/utils/logging.sh"
source "$REPO_ROOT/utils/remote.sh"
source "$REPO_ROOT/utils/state.sh"
source "$REPO_ROOT/utils/env-write.sh"
start_log "chia-farmer-install"
load_all_env

CHIA_MNEMONIC_ENV="$SECRETS_DIR/chia-mnemonic.env"
CHIA_BOOTSTRAP_ENV="$SECRETS_DIR/chia-bootstrap.env"
CHIA_DB_BOOTSTRAP_START_ONLY="${HOMELAB_CHIA_DB_BOOTSTRAP_START_ONLY:-0}"
CHIA_DEFER_DB_START="${HOMELAB_CHIA_DEFER_DB_START:-0}"
ask_mnemonic_hidden(){
  local a="" wc=""
  while true; do
    read -r -s -p "Chia 24-word mnemonic (gizli input, ekranda/logda görünmez): " a; echo
    a="$(echo "$a" | xargs)"
    wc="$(awk '{print NF}' <<<"$a")"
    [[ -n "$a" ]] || { echo "❌ Mnemonic boş olamaz."; continue; }
    [[ "$wc" -eq 24 ]] || { echo "❌ Mnemonic $wc kelime görünüyor; 24 kelime olmalı."; continue; }
    echo "✅ Mnemonic alındı, 24 kelime doğrulandı. İçerik loga basılmadı."
    CHIA_MNEMONIC="$a"
    break
  done
}

if [[ "$CHIA_DB_BOOTSTRAP_START_ONLY" != "1" && ! -f "$CHIA_MNEMONIC_ENV" ]]; then
  if [[ "${HOMELAB_ALLOW_INTERACTIVE_SECRETS:-0}" != "1" && ! -t 0 ]]; then
    echo "SECRETS_MISSING: Chia mnemonic is missing at $CHIA_MNEMONIC_ENV"
    echo "Open the Homelabv4 Secrets page, fill the Chia mnemonic, upload secrets, then rerun the Chia service."
    exit 12
  fi
  echo "⚠️ $CHIA_MNEMONIC_ENV yok. Güvenli fallback olarak burada sorulacak ve başarıdan sonra silinecek."
  ask_mnemonic_hidden
  { write_env_header; write_env_line CHIA_MNEMONIC "$CHIA_MNEMONIC"; } > "$CHIA_MNEMONIC_ENV"
  chmod 600 "$CHIA_MNEMONIC_ENV"
fi

if [[ ! -f "$CHIA_BOOTSTRAP_ENV" ]]; then
  echo "⚠️ $CHIA_BOOTSTRAP_ENV yok. Official latest torrent + TrueNAS cache varsayılanı yazılıyor."
  {
    write_env_header
    write_env_line CHIA_KEY_LABEL "bacmaster"
    write_env_line CHIA_DB_BOOTSTRAP_MODE "official_torrent"
    write_env_line CHIA_DB_MODE "official_torrent"
    write_env_line CHIA_DB_TORRENT_URL "https://torrents.chia.net/databases/mainnet/mainnet.latest.tar.gz.torrent"
    write_env_line CHIA_DB_DOWNLOAD_URL "https://torrents.chia.net/databases/mainnet/mainnet.latest.tar.gz.torrent"
    write_env_line CHIA_DB_MANUAL_PATH ""
    write_env_line CHIA_DB_CACHE_NFS "192.168.50.101:/mnt/tank/chia-db"
    write_env_line CHIA_DB_CACHE_MOUNT "/mnt/chia-db-cache"
    write_env_line CHIA_DB_DOWNLOAD_DIR "/mnt/chia-db-cache"
    write_env_line EXPECTED_CHIA_PLOT_DISKS "5"
  } > "$CHIA_BOOTSTRAP_ENV"
  chmod 600 "$CHIA_BOOTSTRAP_ENV"
fi

if [[ "$CHIA_DB_BOOTSTRAP_START_ONLY" != "1" ]]; then
  # shellcheck disable=SC1090
  source "$CHIA_MNEMONIC_ENV"
fi
# shellcheck disable=SC1090
source "$CHIA_BOOTSTRAP_ENV"
CHIA_DB_MODE="${CHIA_DB_BOOTSTRAP_MODE:-${CHIA_DB_MODE:-fresh}}"
CHIA_DB_DOWNLOAD_URL="${CHIA_DB_DOWNLOAD_URL:-${CHIA_DB_TORRENT_URL:-}}"
CHIA_DB_MANUAL_PATH="${CHIA_DB_MANUAL_PATH:-}"
CHIA_DB_CACHE_NFS="${CHIA_DB_CACHE_NFS:-192.168.50.101:/mnt/tank/chia-db}"
CHIA_DB_CACHE_MOUNT="${CHIA_DB_CACHE_MOUNT:-/mnt/chia-db-cache}"
CHIA_DB_DOWNLOAD_DIR="${CHIA_DB_DOWNLOAD_DIR:-$CHIA_DB_CACHE_MOUNT}"
CHIA_KEY_LABEL="${CHIA_KEY_LABEL:-}"

wait_ssh 107
TMP_REMOTE="/tmp/homelab-chia-install.sh"
MNEMONIC_REMOTE="/tmp/chia-mnemonic.txt"

if [[ "$CHIA_DB_BOOTSTRAP_START_ONLY" != "1" ]]; then
  printf '%s\n' "$CHIA_MNEMONIC" > /tmp/chia-mnemonic.txt
  chmod 600 /tmp/chia-mnemonic.txt
  rscp /tmp/chia-mnemonic.txt 107 "$MNEMONIC_REMOTE" >/dev/null
  shred -u /tmp/chia-mnemonic.txt || rm -f /tmp/chia-mnemonic.txt
fi

cat > /tmp/homelab-chia-install.sh <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
CHIA_HOME="/home/bacmaster/.chia/mainnet"
CHIA_SRC="/opt/chia-blockchain"
MNEMONIC_FILE="/tmp/chia-mnemonic.txt"
DB_MODE="${CHIA_DB_MODE:-fresh}"
DB_URL="${CHIA_DB_DOWNLOAD_URL:-}"
DB_MANUAL_PATH="${CHIA_DB_MANUAL_PATH:-}"
CACHE_NFS="${CHIA_DB_CACHE_NFS:-192.168.50.101:/mnt/tank/chia-db}"
CACHE_MOUNT="${CHIA_DB_CACHE_MOUNT:-/mnt/chia-db-cache}"
DOWNLOAD_DIR="${CHIA_DB_DOWNLOAD_DIR:-$CACHE_MOUNT}"
CHIA_KEY_LABEL="${CHIA_KEY_LABEL:-}"
CHIA_DB_FULL_QUICK_CHECK="${CHIA_DB_FULL_QUICK_CHECK:-0}"
DB_START_ONLY="${HOMELAB_CHIA_DB_BOOTSTRAP_START_ONLY:-0}"
DEFER_DB_START="${HOMELAB_CHIA_DEFER_DB_START:-0}"
DB_TARGET="$CHIA_HOME/db/blockchain_v2_mainnet.sqlite"
CHIA_BIN="/opt/chia-blockchain/venv/bin/chia"
KEY_IMPORT_OK=0

sudo apt update
sudo apt install -y git curl ca-certificates build-essential python3 python3-venv python3-pip python3-dev lsb-release jq tmux unzip rsync aria2 gzip tar pv file nfs-common sqlite3

mount_cache(){
  mkdir -p "$CACHE_MOUNT"
  if ! grep -qs " $CACHE_MOUNT " /etc/fstab; then
    echo "$CACHE_NFS $CACHE_MOUNT nfs defaults,_netdev,x-systemd.automount,nofail 0 0" >> /etc/fstab
  fi
  systemctl daemon-reload
  mount "$CACHE_MOUNT" 2>/dev/null || true
  mountpoint -q "$CACHE_MOUNT"
}

if mount_cache; then
  echo "✅ Chia DB cache mount hazır: $CACHE_MOUNT -> $CACHE_NFS"
  DOWNLOAD_DIR="$CACHE_MOUNT"
else
  echo "⚠️ Chia DB cache mount yok: $CACHE_MOUNT"
  echo "   Büyük torrent/download local diske yapılmayacak; hazır cache yoksa fresh sync'e düşülecek."
fi

if [[ "$DB_START_ONLY" == "1" ]]; then
  echo "Chia DB bootstrap/start mode: using the existing VM107 Chia install."
  [[ -x "$CHIA_BIN" ]] || { echo "Chia binary missing: $CHIA_BIN. Run Chia farmer service install first."; exit 1; }
else
if [[ ! -d "$CHIA_SRC/.git" ]]; then
  sudo git clone https://github.com/Chia-Network/chia-blockchain.git -b latest --recurse-submodules "$CHIA_SRC"
else
  cd "$CHIA_SRC"
  sudo git fetch --all --tags
  sudo git checkout latest || true
  sudo git pull --recurse-submodules || true
  sudo git submodule update --init --recursive
fi

sudo chown -R bacmaster:bacmaster "$CHIA_SRC"
cd "$CHIA_SRC"
sudo -u bacmaster bash -lc 'sh install.sh'
sudo -u bacmaster bash -lc 'cd /opt/chia-blockchain && . ./activate && chia init'
[[ -x "$CHIA_BIN" ]] || { echo "❌ Chia binary bulunamadı: $CHIA_BIN"; exit 1; }

if [[ -s "$MNEMONIC_FILE" ]]; then
  echo "🔐 Chia mnemonic import ediliyor (içerik loga basılmaz)..."
  if sudo -u bacmaster bash -lc "cd /opt/chia-blockchain && . ./activate && printf '%s\n' \"${CHIA_KEY_LABEL:-}\" | chia keys add -f '$MNEMONIC_FILE'"; then
    KEY_IMPORT_OK=1
    shred -u "$MNEMONIC_FILE" || sudo rm -f "$MNEMONIC_FILE"
  else
    echo "❌ Chia key import başarısız; mnemonic dosyası güvenli inceleme için VM107 /tmp altında bırakılmadı."
    shred -u "$MNEMONIC_FILE" || sudo rm -f "$MNEMONIC_FILE"
    exit 1
  fi
fi

fi

find_db_candidate(){
  local root="$1"
  find "$root" -maxdepth 4 -type f \
    \( -name 'blockchain_v2_mainnet.sqlite' -o -name 'blockchain_v2_mainnet.sqlite.gz' -o -name '*.sqlite' -o -name '*.sqlite.gz' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.tgz' \) \
    -printf '%s %p\n' 2>/dev/null | sort -nr | awk '{$1=""; sub(/^ /,""); print; exit}'
}

human_bytes(){ numfmt --to=iec --suffix=B --format='%.1f' "$1" 2>/dev/null || echo "${1}B"; }

show_space_for_import(){
  local src="$1" dest_dir
  dest_dir="$(dirname "$DB_TARGET")"
  echo "📊 Chia DB import alan bilgisi"
  [[ -f "$src" ]] && echo "   Kaynak boyutu : $(human_bytes "$(stat -c '%s' "$src")")"
  echo "   Hedef dizin   : $dest_dir"
  df -h "$dest_dir" 2>/dev/null || true
}

copy_with_progress(){
  local src="$1" dest="$2" bytes
  bytes="$(stat -c '%s' "$src")"
  echo "📥 DB kopyalanıyor: $(human_bytes "$bytes") -> $dest"
  if command -v rsync >/dev/null 2>&1; then
    rsync -ah --info=progress2 "$src" "$dest"
  elif command -v pv >/dev/null 2>&1; then
    pv -ptebar -s "$bytes" "$src" > "$dest"
  else
    echo "⚠️ rsync/pv yok; cp sessiz çalışacak."
    cp "$src" "$dest"
  fi
}

validate_db(){
  local db="$1" bytes
  [[ -s "$db" ]] || { echo "❌ DB boş/0 byte: $db"; return 1; }
  bytes="$(stat -c '%s' "$db")"
  [[ "$bytes" -gt 1000000000 ]] || { echo "❌ DB boyutu şüpheli küçük: $bytes byte"; return 1; }
  file "$db" | grep -qi sqlite || { echo "❌ DB SQLite görünmüyor"; return 1; }
  if command -v sqlite3 >/dev/null 2>&1; then
    if [[ "${CHIA_DB_FULL_QUICK_CHECK:-0}" == "1" ]]; then
      echo "🧪 SQLite full PRAGMA quick_check başlıyor. Büyük DB'de uzun sürebilir; progress göstermemesi normal."
      sqlite3 "file:$db?mode=ro" 'PRAGMA quick_check;' | grep -q ok || { echo "❌ sqlite quick_check başarısız"; return 1; }
    else
      echo "🧪 SQLite lightweight validation yapılıyor; full quick_check r4'te varsayılan olarak atlanır."
      timeout 180 sqlite3 "file:$db?mode=ro" 'PRAGMA schema_version; SELECT count(*) FROM sqlite_master;' >/dev/null || { echo "❌ sqlite lightweight validation başarısız"; return 1; }
    fi
  fi
}

stream_tar_db(){
  local archive="$1" member="" bytes
  bytes="$(stat -c '%s' "$archive")"
  echo "🗜️ tar.gz içinde DB üyesi aranıyor. Büyük arşivlerde bu adım biraz sürebilir."
  member="$(tar -tzf "$archive" | grep -E '(^|/)blockchain_v2_mainnet\.sqlite(\.gz)?$|\.sqlite(\.gz)?$' | head -n1 || true)"
  [[ -n "$member" ]] || { echo "❌ tar.gz içinde sqlite DB bulunamadı"; return 1; }
  echo "🗜️ tar.gz içinden local DB path'e progress ile stream ediliyor: $member"
  if command -v pv >/dev/null 2>&1; then
    if [[ "$member" == *.gz ]]; then
      pv -ptebar -s "$bytes" "$archive" | tar -xzO "$member" | gzip -dc > "$DB_TARGET.tmp"
    else
      pv -ptebar -s "$bytes" "$archive" | tar -xzO "$member" > "$DB_TARGET.tmp"
    fi
  else
    if [[ "$member" == *.gz ]]; then
      tar -xOzf "$archive" "$member" | gzip -dc > "$DB_TARGET.tmp"
    else
      tar -xOzf "$archive" "$member" > "$DB_TARGET.tmp"
    fi
  fi
}

bootstrap_db(){
  sudo -u bacmaster mkdir -p "$CHIA_HOME/db"
  local src="$1" tmpd found
  echo "📦 DB import kaynağı: $src"
  show_space_for_import "$src"
  sudo systemctl stop chia-farmer.service >/dev/null 2>&1 || true
  sudo -u bacmaster "$CHIA_BIN" stop all -d >/dev/null 2>&1 || true
  rm -f "$DB_TARGET.tmp" "$DB_TARGET.tmp-shm" "$DB_TARGET.tmp-wal"
  case "$src" in
    *.tar.gz|*.tgz) stream_tar_db "$src" ;;
    *.sqlite.gz)
      echo "📥 gzip DB decompress progress başlıyor..."
      if command -v pv >/dev/null 2>&1; then pv -ptebar -s "$(stat -c '%s' "$src")" "$src" | gzip -dc > "$DB_TARGET.tmp"; else gzip -dc "$src" > "$DB_TARGET.tmp"; fi ;;
    *.zip)
      tmpd="/tmp/chia-db-unzip-$$"; rm -rf "$tmpd"; mkdir -p "$tmpd"
      echo "📦 zip arşivi açılıyor..."
      unzip -o "$src" -d "$tmpd" >/dev/null
      found="$(find_db_candidate "$tmpd")"
      [[ -n "$found" ]] || { echo "❌ zip içinde DB bulunamadı"; return 1; }
      bootstrap_db "$found"; rm -rf "$tmpd"; return 0 ;;
    *.sqlite) copy_with_progress "$src" "$DB_TARGET.tmp" ;;
    *) file "$src" | grep -qi SQLite && copy_with_progress "$src" "$DB_TARGET.tmp" || { echo "❌ Desteklenmeyen DB dosyası: $src"; return 1; } ;;
  esac
  echo "✅ DB copy/decompress bitti. Validation başlıyor..."
  validate_db "$DB_TARGET.tmp"
  mv "$DB_TARGET.tmp" "$DB_TARGET"
  rm -f "$DB_TARGET.tmp-shm" "$DB_TARGET.tmp-wal"
  sudo chown -R bacmaster:bacmaster "$CHIA_HOME"
  echo "✅ Chia DB hazır: $DB_TARGET ($(du -h "$DB_TARGET" | awk '{print $1}'))"
}

write_chia_service_unit(){
  sudo tee /etc/systemd/system/chia-farmer.service >/dev/null <<'UNIT'
[Unit]
Description=Chia Farmer
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=bacmaster
WorkingDirectory=/opt/chia-blockchain
Environment=CHIA_ROOT=/home/bacmaster/.chia/mainnet
ExecStart=/bin/bash -lc 'cd /opt/chia-blockchain && . ./activate && chia start farmer -r'
ExecStop=/bin/bash -lc 'cd /opt/chia-blockchain && . ./activate && chia stop all -d'
Restart=on-failure
RestartSec=20
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
UNIT

  sudo ln -sf "$CHIA_BIN" /usr/local/bin/chia || true
  sudo systemctl daemon-reload

  CONFIG="/home/bacmaster/.chia/mainnet/config/config.yaml"
  if [[ -f "$CONFIG" ]]; then
    sudo -u bacmaster python3 - <<'PY'
from pathlib import Path
p=Path('/home/bacmaster/.chia/mainnet/config/config.yaml')
text=p.read_text()
lines=text.splitlines(); out=[]; in_h=False; inserted=False
for line in lines:
    if line.startswith('harvester:'):
        in_h=True; out.append(line); continue
    if in_h and line and not line.startswith(' '):
        if not inserted: out.append('  parallel_decompressor_count: 1'); inserted=True
        in_h=False
    if line.strip().startswith('parallel_decompressor_count:'):
        indent=line[:len(line)-len(line.lstrip())]
        out.append(f'{indent}parallel_decompressor_count: 1'); inserted=True
    else:
        out.append(line)
if not inserted:
    if not any(l.startswith('harvester:') for l in out): out += ['harvester:', '  parallel_decompressor_count: 1']
    else:
        new=[]; done=False
        for l in out:
            new.append(l)
            if l.startswith('harvester:') and not done:
                new.append('  parallel_decompressor_count: 1'); done=True
        out=new
p.write_text('\n'.join(out)+'\n')
PY
  fi
}

show_download_hint(){
  cat <<HINT

📥 Chia DB download takip bilgisi
  VM107 cache : $DOWNLOAD_DIR
  Log         : $DOWNLOAD_DIR/aria2.log
  Canlı takip : tail -f $DOWNLOAD_DIR/aria2.log

HINT
}

write_chia_service_unit

if [[ "$DEFER_DB_START" == "1" && "$DB_START_ONLY" != "1" ]]; then
  echo "Chia DB bootstrap/start deferred by Homelabv4."
  echo "Use the Homelabv4 button: Copy Chia DB from tank & Start."
  sudo -u bacmaster "$CHIA_BIN" stop all -d >/dev/null 2>&1 || true
  sudo systemctl disable --now chia-farmer.service >/dev/null 2>&1 || true
  exit 0
fi

# Prefer cache if it already contains a usable DB/archive.
if mountpoint -q "$CACHE_MOUNT"; then
  echo "🔍 Chia DB cache içinde hazır DB/arşiv aranıyor..."
  cached="$(find_db_candidate "$CACHE_MOUNT" || true)"
  if [[ -n "$cached" ]]; then
    bootstrap_db "$cached" || echo "⚠️ Cache bulundu ama import başarısız; seçilen bootstrap moduna geçilecek."
  fi
fi

if [[ "$DB_START_ONLY" == "1" ]]; then
  if [[ ! -f "$DB_TARGET" ]]; then
    echo "Chia DB was not found in the TrueNAS cache and no local DB exists: $CACHE_MOUNT"
    echo "Expected a file like blockchain_v2_mainnet.sqlite under /mnt/tank/chia-db."
    exit 1
  fi
else
case "$DB_MODE" in
  official_torrent)
    DB_URL="${DB_URL:-https://torrents.chia.net/databases/mainnet/mainnet.latest.tar.gz.torrent}"
    ;&
  torrent)
    if [[ ! -f "$DB_TARGET" ]]; then
      if ! mountpoint -q "$CACHE_MOUNT"; then
        echo "⚠️ Cache mount yok; torrent local diske indirilmeyecek. Fresh sync ile devam."
      else
        [[ -n "$DB_URL" && "$DB_URL" != "1" ]] || DB_URL="https://torrents.chia.net/databases/mainnet/mainnet.latest.tar.gz.torrent"
        mkdir -p "$DOWNLOAD_DIR"; chown -R bacmaster:bacmaster "$DOWNLOAD_DIR"
        echo "📦 Chia DB torrent/magnet ile TrueNAS cache'e indiriliyor..."
        show_download_hint
        sudo -u bacmaster aria2c -c --seed-time=0 --summary-interval=30 --download-result=full --console-log-level=notice --log="$DOWNLOAD_DIR/aria2.log" --log-level=notice --dir="$DOWNLOAD_DIR" "$DB_URL" || echo "⚠️ aria2c hata/interrupt döndürdü; mevcut dosyalar kontrol edilecek."
        found="$(find_db_candidate "$DOWNLOAD_DIR" || true)"
        [[ -n "$found" ]] && bootstrap_db "$found" || echo "⚠️ Torrent klasöründe DB dosyası bulunamadı; fresh sync ile devam."
      fi
    fi
    ;;
  url)
    if [[ ! -f "$DB_TARGET" ]]; then
      if ! mountpoint -q "$CACHE_MOUNT"; then
        echo "⚠️ Cache mount yok; URL download local diske yapılmayacak. Fresh sync ile devam."
      elif [[ -n "$DB_URL" ]]; then
        mkdir -p "$DOWNLOAD_DIR"; chown -R bacmaster:bacmaster "$DOWNLOAD_DIR"
        out="$DOWNLOAD_DIR/$(basename "${DB_URL%%\?*}")"
        sudo -u bacmaster curl -fL --progress-bar -C - "$DB_URL" -o "$out"
        bootstrap_db "$out" || echo "⚠️ DB import başarısız; fresh sync ile devam edilecek."
      fi
    fi
    ;;
  manual)
    if [[ ! -f "$DB_TARGET" && -n "$DB_MANUAL_PATH" && -f "$DB_MANUAL_PATH" ]]; then
      bootstrap_db "$DB_MANUAL_PATH" || echo "⚠️ Manuel DB import başarısız; fresh sync ile devam."
    fi
    ;;
  *) echo "ℹ️ Fresh sync seçildi; DB bootstrap atlandı." ;;
esac
fi

sudo tee /etc/systemd/system/chia-farmer.service >/dev/null <<'UNIT'
[Unit]
Description=Chia Farmer
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=bacmaster
WorkingDirectory=/opt/chia-blockchain
Environment=CHIA_ROOT=/home/bacmaster/.chia/mainnet
ExecStart=/bin/bash -lc 'cd /opt/chia-blockchain && . ./activate && chia start farmer -r'
ExecStop=/bin/bash -lc 'cd /opt/chia-blockchain && . ./activate && chia stop all -d'
Restart=on-failure
RestartSec=20
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
UNIT

sudo ln -sf "$CHIA_BIN" /usr/local/bin/chia || true
sudo systemctl daemon-reload
sudo systemctl enable chia-farmer.service

CONFIG="/home/bacmaster/.chia/mainnet/config/config.yaml"
if [[ -f "$CONFIG" ]]; then
  sudo -u bacmaster python3 - <<'PY'
from pathlib import Path
p=Path('/home/bacmaster/.chia/mainnet/config/config.yaml')
text=p.read_text()
lines=text.splitlines(); out=[]; in_h=False; inserted=False
for line in lines:
    if line.startswith('harvester:'):
        in_h=True; out.append(line); continue
    if in_h and line and not line.startswith(' '):
        if not inserted: out.append('  parallel_decompressor_count: 1'); inserted=True
        in_h=False
    if line.strip().startswith('parallel_decompressor_count:'):
        indent=line[:len(line)-len(line.lstrip())]
        out.append(f'{indent}parallel_decompressor_count: 1'); inserted=True
    else:
        out.append(line)
if not inserted:
    if not any(l.startswith('harvester:') for l in out): out += ['harvester:', '  parallel_decompressor_count: 1']
    else:
        new=[]; done=False
        for l in out:
            new.append(l)
            if l.startswith('harvester:') and not done:
                new.append('  parallel_decompressor_count: 1'); done=True
        out=new
p.write_text('\n'.join(out)+'\n')
PY
fi

sudo systemctl restart chia-farmer.service || true
sleep 8
echo "🌱 Chia servis health polling başlıyor..."
for i in {1..12}; do
  echo "--- Chia health attempt $i/12 ---"
  sudo -u bacmaster bash -lc 'cd /opt/chia-blockchain && . ./activate && chia show -s || true'
  sudo -u bacmaster bash -lc 'cd /opt/chia-blockchain && . ./activate && chia farm summary || true'
  if sudo -u bacmaster bash -lc 'cd /opt/chia-blockchain && . ./activate && chia show -s 2>/dev/null' | grep -Eiq 'Current Blockchain Status|Synced|Not Synced|Peak'; then
    break
  fi
  sleep 15
done
REMOTE

rscp /tmp/homelab-chia-install.sh 107 "$TMP_REMOTE" >/dev/null
{
  printf 'CHIA_DB_MODE=%q\n' "${CHIA_DB_MODE:-fresh}"
  printf 'CHIA_DB_DOWNLOAD_URL=%q\n' "${CHIA_DB_DOWNLOAD_URL:-}"
  printf 'CHIA_DB_MANUAL_PATH=%q\n' "${CHIA_DB_MANUAL_PATH:-}"
  printf 'CHIA_DB_CACHE_NFS=%q\n' "${CHIA_DB_CACHE_NFS:-192.168.50.101:/mnt/tank/chia-db}"
  printf 'CHIA_DB_CACHE_MOUNT=%q\n' "${CHIA_DB_CACHE_MOUNT:-/mnt/chia-db-cache}"
  printf 'CHIA_DB_DOWNLOAD_DIR=%q\n' "${CHIA_DB_DOWNLOAD_DIR:-/mnt/chia-db-cache}"
  printf 'CHIA_KEY_LABEL=%q\n' "${CHIA_KEY_LABEL:-}"
  printf 'CHIA_DB_FULL_QUICK_CHECK=%q\n' "${CHIA_DB_FULL_QUICK_CHECK:-0}"
  printf 'HOMELAB_CHIA_DB_BOOTSTRAP_START_ONLY=%q\n' "${CHIA_DB_BOOTSTRAP_START_ONLY:-0}"
  printf 'HOMELAB_CHIA_DEFER_DB_START=%q\n' "${CHIA_DEFER_DB_START:-0}"
} > /tmp/chia-remote.env
rscp /tmp/chia-remote.env 107 "/tmp/chia-remote.env" >/dev/null
rm -f /tmp/chia-remote.env
rssh 107 "chmod +x $TMP_REMOTE && sudo bash -c 'set -a; source /tmp/chia-remote.env; set +a; $TMP_REMOTE; rm -f /tmp/chia-remote.env'"
rm -f /tmp/homelab-chia-install.sh

if [[ "$CHIA_DB_BOOTSTRAP_START_ONLY" != "1" && -f "$CHIA_MNEMONIC_ENV" ]]; then
  echo "🧹 Chia mnemonic secret dosyası siliniyor: $CHIA_MNEMONIC_ENV"
  shred -u "$CHIA_MNEMONIC_ENV" || rm -f "$CHIA_MNEMONIC_ENV"
fi

echo "🔧 Chia plot disk / compressed plot repair uygulanıyor..."
if [[ "$CHIA_DEFER_DB_START" == "1" && "$CHIA_DB_BOOTSTRAP_START_ONLY" != "1" ]]; then
  export HOMELAB_CHIA_NO_START=1
fi
bash "$REPO_ROOT/maintenance/repair/repair-chia-plot-disks.sh" || echo "⚠️ Chia plot disk repair tamamlanamadı; maintenance menüsünden tekrar çalıştırabilirsin."

state_set chia_farmer_installed true
state_set chia_farmer_installed_at "$(date -Is)"
if [[ "$CHIA_DB_BOOTSTRAP_START_ONLY" == "1" ]]; then
  state_set chia_db_bootstrap_pending false
  state_set chia_farmer_active true
  state_set chia_farmer_started_at "$(date -Is)"
elif [[ "$CHIA_DEFER_DB_START" == "1" ]]; then
  state_set chia_db_bootstrap_pending true
  state_set chia_farmer_active false
fi
echo "✅ Chia farmer kurulumu tamamlandı."
