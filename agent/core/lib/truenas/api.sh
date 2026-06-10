#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${HOMELAB_ROOT:-}" ]]; then
  HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

source "$HOMELAB_ROOT/lib/core/env.sh"
load_all_env

TRUENAS_API_ENV="${TRUENAS_API_ENV:-$SECRETS_DIR/truenas-api.env}"
TRUENAS_IP_DEFAULT="${TRUENAS_IP_DEFAULT:-192.168.50.101}"

load_truenas_api_env() {
  [[ -f "$TRUENAS_API_ENV" ]] || {
    echo "Hata: TrueNAS API env bulunamadi: $TRUENAS_API_ENV"
    return 1
  }
  set -a
  # shellcheck disable=SC1090
  source "$TRUENAS_API_ENV"
  set +a
  TRUENAS_IP="${TRUENAS_HOST:-${TRUENAS_IP:-$TRUENAS_IP_DEFAULT}}"
  : "${TRUENAS_API_KEY:?TRUENAS_API_KEY eksik. $TRUENAS_API_ENV dosyasini kontrol et.}"
  TN_API="http://${TRUENAS_IP}/api/v2.0"
  export TRUENAS_IP TN_API TRUENAS_API_KEY
}

tn_get() {
  local endpoint="$1"
  curl -sk --connect-timeout 10 --max-time 30 \
    -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
    "$TN_API/$endpoint"
}

tn_post() {
  local endpoint="$1" payload="$2"
  curl -sk --connect-timeout 10 --max-time 30 \
    -X POST \
    -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$TN_API/$endpoint"
}

tn_put() {
  local endpoint="$1" payload="$2"
  curl -sk --connect-timeout 10 --max-time 30 \
    -X PUT \
    -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$TN_API/$endpoint"
}

tn_get_json_retry() {
  local endpoint="$1" outfile="$2" tries="${3:-30}" delay="${4:-5}"
  local code i
  for i in $(seq 1 "$tries"); do
    code="$(curl -sk --connect-timeout 10 --max-time 30 \
      -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
      -o "$outfile" -w "%{http_code}" \
      "$TN_API/$endpoint" || true)"
    if [[ "$code" =~ ^2[0-9][0-9]$ ]] && python3 -m json.tool "$outfile" >/dev/null 2>&1; then
      return 0
    fi
    echo "TrueNAS endpoint bekleniyor: $endpoint (attempt $i/$tries, HTTP ${code:-curl_failed})"
    sleep "$delay"
  done
  echo "Hata: TrueNAS endpoint hazir degil veya JSON donmuyor: $endpoint"
  cat "$outfile" 2>/dev/null || true
  return 1
}

truenas_api_readiness() {
  load_truenas_api_env
  tn_get_json_retry "system/info" /tmp/truenas-info.json 30 5
  for ep in group user pool/dataset sharing/nfs sharing/smb; do
    tn_get_json_retry "$ep" "/tmp/truenas-ready-${ep//\//-}.json" 30 5
  done
}
