#!/usr/bin/env bash
set -u -o pipefail

OUT="/root/homelab-support-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
chmod 700 "$OUT" 2>/dev/null || true

note(){ printf '%s\n' "$*" | tee -a "$OUT/support-bundle-notes.txt" >/dev/null; }

run_diag(){
  local title="$1"; shift || true
  local cmd="${1:-}"
  echo
  echo "--- $title ---"
  if [[ -z "$cmd" ]]; then
    echo "no command supplied"
    return 0
  fi
  if command -v "$cmd" >/dev/null 2>&1; then
    "$@" 2>&1 || echo "WARN: command failed rc=$?: $*"
  else
    echo "WARN: command not found: $cmd"
  fi
}

redact_file(){
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")" 2>/dev/null || true
  [[ -f "$src" ]] || return 0
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$src" "$dst" <<'PYREDACT' || echo "WARN: redact failed, secret file skipped" >> /dev/null
from pathlib import Path
import re, sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(errors='ignore')
patterns=[
    r'(?im)^([^#\n]*(?:PASS|PASSWORD|SECRET|TOKEN|API_KEY|CLIENT_SECRET|CLIENTSECRET|APP_PASS|KEY|MNEMONIC)[A-Za-z0-9_]*\s*=\s*).+$',
    r'(?i)("(?:password|token|secret|api[_-]?key|client[_-]?secret|clientSecret|app[_-]?pass|mnemonic)"\s*:\s*")[^"]+("?)',
    r'GOCSPX-[A-Za-z0-9_-]+',
    r'(?i)(clientSecret["\':= ]+)[A-Za-z0-9_./+-]+',
    r'(?i)(client_secret["\':= ]+)[A-Za-z0-9_./+-]+',
]
text=re.sub(patterns[0], r'\1<REDACTED>', text)
text=re.sub(patterns[1], r'\1<REDACTED>\2', text)
text=re.sub(patterns[2], 'GOCSPX-<REDACTED>', text)
text=re.sub(patterns[3], r'\1<REDACTED>', text)
text=re.sub(patterns[4], r'\1<REDACTED>', text)
dst.write_text(text)
PYREDACT
  else
    note "WARN: python3 missing; secret/env file skipped for safety: $src"
  fi
}

copy_dir_if_exists(){
  local src="$1" dst="$2"
  [[ -d "$src" ]] || return 0
  cp -a "$src" "$dst" 2>/dev/null || note "WARN: could not copy directory: $src"
}

echo "📦 Redacted support bundle hazırlanıyor: $OUT"

{
  echo "date=$(date -Is 2>/dev/null || date)"
  run_diag "uname" uname -a
  run_diag "ip addr" ip a
  run_diag "ip route" ip r
  run_diag "df" df -h
  run_diag "lsblk filesystem" lsblk -f
  run_diag "lsblk detailed" lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,FSTYPE,LABEL
  echo
  echo "--- /dev/disk/by-id ---"
  ls -l /dev/disk/by-id 2>&1 || echo "WARN: /dev/disk/by-id okunamadı"
  run_diag "pvesm status" pvesm status
  run_diag "qm list" qm list
} > "$OUT/system.txt" 2>&1 || true

if command -v qm >/dev/null 2>&1; then
  mkdir -p "$OUT/qm-config"
  for vmid in 101 102 103 104 105 106 107 110; do
    qm config "$vmid" > "$OUT/qm-config/${vmid}.txt" 2>&1 || true
  done
fi

if command -v journalctl >/dev/null 2>&1; then
  journalctl -n 500 --no-pager > "$OUT/journal-last500.txt" 2>&1 || true
else
  echo "journalctl command not found" > "$OUT/journal-last500.txt"
fi

if command -v dmesg >/dev/null 2>&1; then
  { dmesg -T 2>&1 || true; } | grep -Ei 'ata|resetting link|I/O error|failed command|ST4000|Seagate|TOSHIBA|nvme|zfs' > "$OUT/dmesg-disk-errors.txt" 2>&1 || true
else
  echo "dmesg command not found" > "$OUT/dmesg-disk-errors.txt"
fi

copy_dir_if_exists /root/homelab-logs "$OUT/homelab-logs"
copy_dir_if_exists /root/homelab-state "$OUT/homelab-state"
copy_dir_if_exists /root/homelabv3.1-state "$OUT/homelabv3.1-state"
copy_dir_if_exists /root/homelabv3.1.1-state "$OUT/homelabv3.1.1-state"
copy_dir_if_exists /root/homelabv3.1.1-r2-state "$OUT/homelabv3.1.1-r2-state"

if [[ -d /opt/homelab ]]; then
  while IFS= read -r f; do
    rel="${f#/}"
    case "$(basename "$f")" in
      docker-compose.yml|compose.yml)
        mkdir -p "$OUT/$(dirname "$rel")" 2>/dev/null || true
        cp "$f" "$OUT/$rel" 2>/dev/null || true
        ;;
      .env|*.env)
        redact_file "$f" "$OUT/$rel.redacted"
        ;;
    esac
  done < <(find /opt/homelab -maxdepth 4 \( -name 'docker-compose.yml' -o -name 'compose.yml' -o -name '.env' -o -name '*.env' \) -print 2>/dev/null || true)
fi

if [[ -d /root/homelab-secrets ]]; then
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    case "$(basename "$f")" in
      chia-mnemonic.env)
        note "ℹ️ chia-mnemonic.env support bundle dışında bırakıldı."
        continue
        ;;
    esac
    redact_file "$f" "$OUT/${f#/}.redacted"
  done < <(find /root/homelab-secrets -maxdepth 1 -type f -name '*.env' -print 2>/dev/null || true)
fi

TAR_RC=0
if command -v tar >/dev/null 2>&1; then
  tar --ignore-failed-read -czf "$OUT.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")" 2> "$OUT/tar-warnings.txt" || TAR_RC=$?
else
  note "WARN: tar command not found"
  TAR_RC=127
fi

if [[ -f "$OUT.tar.gz" ]]; then
  echo "✅ Oluşturuldu: $OUT.tar.gz"
  echo "ℹ️ .env/secret değerleri redacted olarak eklendi; raw secret kopyalanmadı."
  exit 0
fi

echo "❌ Support bundle tar oluşturulamadı. Klasör hazır: $OUT"
exit "$TAR_RC"
