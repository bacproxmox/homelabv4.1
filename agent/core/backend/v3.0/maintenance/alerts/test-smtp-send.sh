#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/env-loader.sh"
source "$SCRIPT_DIR/../../utils/logging.sh"
start_log "test-smtp-send"
load_all_env

SERVICES_ALL=(nextcloud immich seerr uptime-kuma truenas)
SERVICE="${1:-nextcloud}"

usage(){ echo "Kullanım: $0 {nextcloud|immich|seerr|uptime-kuma|truenas|all}"; }

pass_var_for(){
  case "$1" in
    nextcloud) echo "ZOHO_NEXTCLOUD_APP_PASS" ;;
    immich) echo "ZOHO_IMMICH_APP_PASS" ;;
    jellyseerr|seerr) echo "ZOHO_SEERR_APP_PASS" ;;
    uptime-kuma|uptime) echo "ZOHO_UPTIME_KUMA_APP_PASS" ;;
    truenas) echo "ZOHO_TRUENAS_APP_PASS" ;;
    *) return 1 ;;
  esac
}

test_one(){
  local service="$1" pass_var app_pass
  pass_var="$(pass_var_for "$service")" || { usage; return 2; }
  app_pass="${!pass_var:-}"

  echo
  echo "========================================="
  echo " SMTP test: $service"
  echo "========================================="
  echo "SMTP host : ${SMTP_HOST:-smtppro.zoho.eu}"
  echo "SMTP port : ${SMTP_PORT:-465}"
  echo "SMTP user : ${SMTP_FROM:-admin@bacmastercloud.com}"
  echo "Pass var  : $pass_var"
  echo "Test to   : ${SMTP_TEST_TO:-admin@bacmastercloud.com}"

  if [[ -z "$app_pass" ]]; then
    echo "❌ $pass_var boş. /root/homelab-secrets/smtp.env içinde kontrol et."
    return 1
  fi

  SERVICE="$service" APP_PASS="$app_pass" SMTP_HOST="${SMTP_HOST:-smtppro.zoho.eu}" SMTP_PORT="${SMTP_PORT:-465}" SMTP_FROM="${SMTP_FROM:-admin@bacmastercloud.com}" SMTP_TEST_TO="${SMTP_TEST_TO:-admin@bacmastercloud.com}" python3 - <<'PYMAIL'
import smtplib, ssl, os, sys
from email.message import EmailMessage
service=os.environ.get('SERVICE','unknown')
host=os.environ.get('SMTP_HOST','smtppro.zoho.eu')
port=int(os.environ.get('SMTP_PORT','465'))
user=os.environ.get('SMTP_FROM','admin@bacmastercloud.com')
password=os.environ.get('APP_PASS')
to=os.environ.get('SMTP_TEST_TO','admin@bacmastercloud.com')
msg=EmailMessage()
msg['From']=user
msg['To']=to
msg['Subject']=f'Homelab v2.4.6 SMTP test - {service}'
msg.set_content(f'Homelab v2.4.6 SMTP test başarılı. Service profile: {service}')
try:
    ctx = ssl.create_default_context()
    if port == 465:
        with smtplib.SMTP_SSL(host, port, timeout=20, context=ctx) as s:
            s.login(user, password)
            s.send_message(msg)
    else:
        with smtplib.SMTP(host, port, timeout=20) as s:
            s.ehlo()
            s.starttls(context=ctx)
            s.login(user, password)
            s.send_message(msg)
    print(f'✅ Test mail gönderildi: {to} / profile={service}')
except smtplib.SMTPAuthenticationError as e:
    print(f'❌ SMTP authentication failed for profile={service}: {e.smtp_code} {e.smtp_error!r}')
    print('')
    print('Kontrol listesi:')
    print('- Zoho app-specific password doğru mu / expire olmadı mı?')
    print('- Doğru env değişkeni kullanılıyor mu?')
    print('- SMTP username/from admin@bacmastercloud.com ile aynı mı?')
    print('- Zoho hesabında 2FA/app password ayarları aktif mi?')
    print('- Yeni app password aldıysan /root/homelab-secrets/smtp.env güncel mi?')
    sys.exit(10)
except Exception as e:
    print(f'❌ SMTP test failed for profile={service}: {type(e).__name__}: {e}')
    sys.exit(11)
PYMAIL
}

if [[ "$SERVICE" == "all" ]]; then
  fail=0
  for s in "${SERVICES_ALL[@]}"; do
    test_one "$s" || fail=1
  done
  if [[ "$fail" -eq 0 ]]; then
    echo
    echo "✅ Tüm SMTP profilleri başarılı."
  else
    echo
    echo "❌ Bir veya daha fazla SMTP profili başarısız. Log: $LOG_FILE"
  fi
  exit "$fail"
else
  test_one "$SERVICE"
fi
