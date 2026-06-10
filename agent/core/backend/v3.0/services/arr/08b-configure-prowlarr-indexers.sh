#!/usr/bin/env bash
set -euo pipefail

export TERM=xterm

ARR_HOST="192.168.50.102"
ARR_SSH_USER="bacmaster"

PROWLARR_URL="http://192.168.50.102:9696"
PROWLARR_CONFIG="/opt/homelab/arr/config/prowlarr/config.xml"

NO_FLARE_INDEXERS=(
  "bangumi-moe"
  "limetorrents"
  "nyaasi"
  "thepiratebay"
  "torrentdownloads"
  "uindex"
)

FLARE_INDEXERS=(
  # v2.4: Cloudflare-heavy definitions disabled by default.
)

echo
echo "🧲 Homelab v2.3 - Prowlarr Indexer Automation"
echo "📍 ARR VM       : ${ARR_SSH_USER}@${ARR_HOST}"
echo "📍 Prowlarr URL : ${PROWLARR_URL}"
echo

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    apt-get update -y
    apt-get install -y "$1"
  }
}

need_cmd curl
need_cmd jq
need_cmd ssh

ssh_vm() {
  ssh \
    -o StrictHostKeyChecking=no \
    "${ARR_SSH_USER}@${ARR_HOST}" \
    "$@"
}

echo "🔑 API key okunuyor..."

PROWLARR_API_KEY="$(ssh_vm \
  "grep -oPm1 '(?<=<ApiKey>)[^<]+' '${PROWLARR_CONFIG}'" || true)"

if [[ -z "$PROWLARR_API_KEY" ]]; then
  echo "❌ API key okunamadı."
  echo "Config yolu: ${PROWLARR_CONFIG}"
  exit 1
fi

echo "✅ API key okundu."

api_get() {
  curl -fsS \
    -H "X-Api-Key: ${PROWLARR_API_KEY}" \
    "${PROWLARR_URL}/api/v1/$1"
}

api_post() {
  local endpoint="$1"
  local data="$2"

  curl -fsS -X POST \
    -H "X-Api-Key: ${PROWLARR_API_KEY}" \
    -H "Content-Type: application/json" \
    "${PROWLARR_URL}/api/v1/${endpoint}" \
    -d "${data}"
}

echo
echo "⏳ Prowlarr API bekleniyor..."

for i in {1..30}; do
  if api_get "system/status" >/dev/null 2>&1; then
    echo "✅ API hazır."
    break
  fi

  if [[ "$i" -eq 30 ]]; then
    echo "❌ Prowlarr API cevap vermedi."
    exit 1
  fi

  sleep 2
done

echo
echo "📦 Indexer schema listesi alınıyor..."
SCHEMA_JSON="$(api_get "indexer/schema")"

get_tag_id() {
  local tag_name="$1"
  local existing

  existing="$(api_get "tag" | jq -r --arg n "$tag_name" '.[] | select(.label==$n) | .id' | head -n1)"

  if [[ -n "$existing" && "$existing" != "null" ]]; then
    echo "$existing"
    return
  fi

  api_post "tag" "$(jq -nc --arg label "$tag_name" '{label:$label}')" | jq -r '.id'
}

FLARE_TAG_ID="$(get_tag_id "flaresolverr")"

indexer_exists() {
  local def="$1"

  api_get "indexer" | jq -e --arg d "$def" '
    .[] |
    select(
      (.fields[]? | select(.name=="definitionFile" and .value==$d))
      or
      (.name | ascii_downcase | contains($d | ascii_downcase))
    )
  ' >/dev/null
}

add_indexer() {
  local def="$1"
  local use_flare="$2"

  echo
  echo "➕ Indexer kontrol: ${def}"

  if indexer_exists "$def"; then
    echo "✅ Zaten mevcut, geçiliyor."
    return
  fi

  local schema
  schema="$(echo "$SCHEMA_JSON" | jq -c --arg d "$def" '
    .[]
    | select(.implementation=="Cardigann")
    | select(.fields[]? | select(.name=="definitionFile" and .value==$d))
  ' | head -n1)"

  if [[ -z "$schema" ]]; then
    echo "⚠️ Schema bulunamadı, atlandı: ${def}"
    return
  fi

  local payload
  payload="$(echo "$schema" | jq '
    del(
      .id,
      .infoLink,
      .lastSync,
      .sortName,
      .protocols,
      .language,
      .privacy,
      .capabilities
    )
    | .enable = true
    | .priority = 25
    | .appProfileId = 1
  ')"

  if [[ "$use_flare" == "yes" ]]; then
    payload="$(echo "$payload" | jq --argjson tid "$FLARE_TAG_ID" '.tags = [$tid]')"
  else
    payload="$(echo "$payload" | jq '.tags = []')"
  fi

  http_code="$(curl -s \
    -o /tmp/prowlarr-indexer-response.json \
    -w "%{http_code}" \
    -X POST \
    -H "X-Api-Key: ${PROWLARR_API_KEY}" \
    -H "Content-Type: application/json" \
    "${PROWLARR_URL}/api/v1/indexer" \
    -d "${payload}")"

  if [[ "$http_code" == "201" ]]; then
    echo "✅ Eklendi: ${def}"
  else
    echo "⚠️ Eklenemedi/atlandı: ${def} HTTP ${http_code}"
    cat /tmp/prowlarr-indexer-response.json || true
    echo
  fi
}

echo
echo "🌐 FlareSolverr olmadan çalışan indexerlar ekleniyor..."

for idx in "${NO_FLARE_INDEXERS[@]}"; do
  add_indexer "$idx" "no"
done

echo
echo "🔥 FlareSolverr ile çalışan indexerlar ekleniyor..."

for idx in "${FLARE_INDEXERS[@]}"; do
  add_indexer "$idx" "yes"
done

echo
echo "✅ Prowlarr indexer otomasyonu tamamlandı."
echo "🔗 Prowlarr: ${PROWLARR_URL}"
echo