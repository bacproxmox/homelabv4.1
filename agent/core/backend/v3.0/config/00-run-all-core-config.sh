#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils/env-loader.sh"
source "$ROOT_DIR/utils/logging.sh"
start_log "run-all-core-config"

run(){
  echo
  echo "▶️ $*"
  if bash "$ROOT_DIR/$1"; then
    return 0
  else
    local c=$?
    echo "❌ Script hata verdi ($c): $1"
    return "$c"
  fi
}

run_jellyfin_with_wizard_gate(){
  echo
  echo "▶️ config/jellyfin/01-jellyfin-libraries-and-users.sh"
  if bash "$ROOT_DIR/config/jellyfin/01-jellyfin-libraries-and-users.sh"; then
    return 0
  fi
  local c=$?
  if [[ "$c" == "20" ]]; then
    if [[ "${HOMELAB_NO_JELLYFIN_WIZARD_GATE:-0}" == "1" || "${HOMELAB_NO_JELLYFIN_WIZARD_PROMPT:-0}" == "1" ]]; then
      echo
      echo "Jellyfin wizard/admin hazir degil; v3.1 guided modda manuel bekleme yapilmadi."
      echo "Bu durum final ozette uyari olarak raporlanacak; TrueNAS disinda adim arasi onay beklenmez."
      return "$c"
    fi
    cat <<'MSG'

⚠️ Jellyfin wizard tamamlanmamış.
Tarayıcıdan aç: http://192.168.50.106:8096
Admin kullanıcı: bacmaster
Şifre: /root/homelab-secrets/users.env içindeki BACMASTER_PASS

Wizard bitince Enter'a bas. Aynı script otomatik tekrar çalışacak.
MSG
    read -r -p "Jellyfin wizard tamamlandıysa Enter..." _
    bash "$ROOT_DIR/config/jellyfin/01-jellyfin-libraries-and-users.sh"
    return $?
  fi
  return "$c"
}

echo
cat <<'BANNER'
=========================================
 Homelab v2.4.7 - Run all core config
=========================================
BANNER

echo "🧩 Core config scriptleri sırayla çalışacak. Tek hata yüzünden kalan scriptler atlanmayacak."

failures=()
warnings=()
run_step(){
  local script="$1"
  if [[ "$script" == "__jellyfin__" ]]; then
    if run_jellyfin_with_wizard_gate; then return 0; fi
    local c=$?
    if [[ "$c" == "20" ]]; then
      warnings+=("config/jellyfin/01-jellyfin-libraries-and-users.sh:$c")
      echo "Uyari: Jellyfin wizard/admin henuz hazir degil; bu adim sonradan tekrar calistirilabilir."
      return 0
    fi
    failures+=("config/jellyfin/01-jellyfin-libraries-and-users.sh:$c")
    echo "⚠️ Devam ediliyor; final özetinde raporlanacak: Jellyfin config ($c)"
    return 0
  fi

  if run "$script"; then
    return 0
  else
    local c=$?
    failures+=("$script:$c")
    echo "⚠️ Devam ediliyor; final özetinde raporlanacak: $script ($c)"
    return 0
  fi
}

# ARR/auth/integration/language layer
run_step config/arr/05-configure-service-auth.sh
run_step config/qbittorrent/01-qbittorrent-auto-config.sh
# Canonical Prowlarr indexers must exist before ARR app/indexer sync.
run_step config/prowlarr/01-add-canonical-indexers.sh
run_step config/arr/06-configure-arr-integrations.sh
run_step config/arr/07-sonarr-radarr-language-policy.sh
run_step config/bazarr/07-bazarr-languages-and-media-management.sh

# Media/UI/app config layer
run_step __jellyfin__
run_step config/seerr/02-seerr-full-auto-config.sh
run_step config/nextcloud/01-nextcloud-local-and-cloudflare-fix.sh
run_step config/nextcloud/02-nextcloud-smtp-google-and-users.sh
run_step config/nextcloud/03-nextcloud-smtp-config.sh
run_step config/nextcloud/04-bacscloud-production-hardening.sh
run_step config/nextcloud/06-bacscloud-admin-overview-cleanup.sh
run_step config/nextcloud/07-bacscloud-social-login-and-registration.sh
run_step config/nextcloud/05-bacscloud-access-verify.sh
run_step config/immich/02-immich-users-smtp-external-library-note.sh
run_step config/ollama/02-fix-openwebui-admin.sh

# Auth/monitoring helpers
run_step config/google-oauth/14c-configure-google-oauth-all.sh
run_step config/smtp/01-write-service-smtp-reference.sh
run_step config/uptime-kuma/02-uptime-kuma-auto-config.sh
run_step config/pbs/01-pbs-backup-automation.sh

echo
if (( ${#failures[@]} == 0 )); then
  if (( ${#warnings[@]} > 0 )); then
    echo "Uyari: Core config tamamlandi ama tekrar denenebilir adimlar var:"
    printf '  - %s\n' "${warnings[@]}"
    echo "Bu uyarilar kurulum sonucunu basarisiz saydirmaz."
  fi
  echo "✅ Tüm core config scriptleri başarıyla tamamlandı."
  exit 0
else
  echo "⚠️ Core config tamamlandı ama bazı scriptler hata verdi:"
  printf '  - %s\n' "${failures[@]}"
  echo "Loglar: /root/homelab-logs"
  exit 1
fi
