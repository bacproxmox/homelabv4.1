#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "clear-nextcloud-preinstall-backups"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
TARGET="/mnt/nextcloud/data"
if [[ ! -d "$TARGET" ]]; then echo "❌ $TARGET yok"; exit 1; fi
mapfile -t backups < <(find "$TARGET" -maxdepth 1 -type d -name '*.preinstall-backup-*' | sort)
if [[ "${#backups[@]}" -eq 0 ]]; then
  echo "✅ Silinecek preinstall backup bulunamadı."
  exit 0
fi
echo "⚠️ Aşağıdaki Nextcloud preinstall admin backup klasörleri silinecek:"
printf '  - %s\n' "${backups[@]}"
read -r -p "Silmek için DELETE yaz: " answer
if [[ "$answer" != "DELETE" ]]; then
  echo "İptal edildi."
  exit 0
fi
for d in "${backups[@]}"; do
  rm -rf -- "$d"
  echo "🧹 Silindi: $d"
done
echo "✅ Temizlik tamamlandı."
REMOTE
chmod +x "$TMP"
rscp "$TMP" 104 /tmp/clear-nextcloud-preinstall-backups.sh
rssh 104 "sudo bash /tmp/clear-nextcloud-preinstall-backups.sh"
