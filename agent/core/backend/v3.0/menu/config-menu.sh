#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "config-menu"
run(){ echo; echo "▶️ $*"; if bash "$ROOT_DIR/$1"; then return 0; else local c=$?; echo "❌ Script hata verdi ($c): $1"; return "$c"; fi; }
run_jellyfin_with_wizard_gate(){
  echo; echo "▶️ config/jellyfin/01-jellyfin-libraries-and-users.sh"
  if bash "$ROOT_DIR/config/jellyfin/01-jellyfin-libraries-and-users.sh"; then return 0; fi
  local c=$?
  if [[ "$c" == "20" ]]; then
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
run_all_core(){
  echo
  echo "🧩 Run all core config scripts başlıyor. v2.4 artık tek hata yüzünden kalan scriptleri atlamaz."
  local -a failures=()
  run_step(){
    local script="$1"
    if [[ "$script" == "__jellyfin__" ]]; then
      if run_jellyfin_with_wizard_gate; then return 0; fi
      local c=$?
      failures+=("config/jellyfin/01-jellyfin-libraries-and-users.sh:$c")
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
  run_step config/arr/05-configure-service-auth.sh
  # Canonical Prowlarr indexers must exist before ARR app/indexer sync.
  run_step config/prowlarr/01-add-canonical-indexers.sh
  run_step config/arr/06-configure-arr-integrations.sh
  run_step config/arr/07-sonarr-radarr-language-policy.sh
  run_step config/bazarr/07-bazarr-languages-and-media-management.sh
  run_step __jellyfin__
  run_step config/seerr/02-seerr-full-auto-config.sh
  run_step config/nextcloud/01-nextcloud-local-and-cloudflare-fix.sh
  run_step config/nextcloud/02-nextcloud-smtp-google-and-users.sh
  run_step config/nextcloud/03-nextcloud-smtp-config.sh
  run_step config/nextcloud/04-bacscloud-production-hardening.sh
  run_step config/nextcloud/05-bacscloud-access-verify.sh
  run_step config/immich/02-immich-users-smtp-external-library-note.sh
  run_step config/ollama/02-fix-openwebui-admin.sh
  run_step config/google-oauth/14c-configure-google-oauth-all.sh
  run_step config/smtp/01-write-service-smtp-reference.sh
  run_step config/uptime-kuma/02-uptime-kuma-auto-config.sh
run_step config/pbs/01-pbs-backup-automation.sh
  echo
  if (( ${#failures[@]} == 0 )); then
    echo "✅ Tüm core config scriptleri başarıyla tamamlandı."
  else
    echo "⚠️ Core config tamamlandı ama bazı scriptler hata verdi:"
    printf '  - %s\n' "${failures[@]}"
    echo "Loglar: /root/homelab-logs"
    return 1
  fi
}

while true; do
  clear || true
  cat <<'MENU'
=========================================
 Homelab v2.4.7 - Config Menu
=========================================
1) Configure service auth + qBittorrent policy
2) Configure ARR integrations (qBit clients / Prowlarr apps / FlareSolverr)
3) Configure Sonarr/Radarr language policy
4) Add Prowlarr canonical indexers
5) Configure Bazarr languages + media management
6) Configure Jellyfin users/libraries/HW acceleration
7) Configure Seerr full-auto
8) Configure Bacscloud local/users + SMTP + hardening + social login
9) Configure Immich users/storage/external libraries
10) Reset + final configure Immich
11) Fix OpenWebUI admin
12) Google OAuth manager
13) SMTP reference + tests helper
14) Uptime Kuma auto-config / SMTP
15) PBS backup automation
16) Run all core config scripts
17) Additionals menu
18) Exit
MENU
  read -r -p "Seçim: " choice
  case "$choice" in
    1) run config/arr/05-configure-service-auth.sh; run config/qbittorrent/01-qbittorrent-auto-config.sh ;;
    2) run config/arr/06-configure-arr-integrations.sh ;;
    3) run config/arr/07-sonarr-radarr-language-policy.sh ;;
    4) run config/prowlarr/01-add-canonical-indexers.sh ;;
    5) run config/bazarr/07-bazarr-languages-and-media-management.sh ;;
    6) run_jellyfin_with_wizard_gate ;;
    7) run config/seerr/02-seerr-full-auto-config.sh ;;
    8) run config/nextcloud/01-nextcloud-local-and-cloudflare-fix.sh; run config/nextcloud/02-nextcloud-smtp-google-and-users.sh; run config/nextcloud/03-nextcloud-smtp-config.sh; run config/nextcloud/04-bacscloud-production-hardening.sh; run config/nextcloud/06-bacscloud-admin-overview-cleanup.sh; run config/nextcloud/07-bacscloud-social-login-and-registration.sh; run config/nextcloud/05-bacscloud-access-verify.sh ;;
    9) run config/immich/02-immich-users-smtp-external-library-note.sh ;;
    10) run config/immich/03-immich-reset-final-config.sh ;;
    11) run config/ollama/02-fix-openwebui-admin.sh ;;
    12) run config/google-oauth/14c-configure-google-oauth-all.sh ;;
    13) run config/smtp/01-write-service-smtp-reference.sh ;;
    14) run config/uptime-kuma/02-uptime-kuma-auto-config.sh ;;
    15) run config/pbs/01-pbs-backup-automation.sh ;;
    16) run config/00-run-all-core-config.sh || true ;;
    17) bash "$ROOT_DIR/menu/additionals-menu.sh" ;;
    18) exit 0 ;;
    *) echo "Geçersiz seçim"; sleep 2 ;;
  esac
  read -r -p "Devam için Enter..." _
done
