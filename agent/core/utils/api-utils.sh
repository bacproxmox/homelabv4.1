#!/usr/bin/env bash
set -Eeuo pipefail

json_escape() { jq -Rn --arg v "${1-}" '$v'; }

http_get() {
  local url="$1" key="${2-}"
  if [[ -n "$key" ]]; then
    curl -fsS -H "X-Api-Key: $key" "$url"
  else
    curl -fsS "$url"
  fi
}

http_post_json() {
  local url="$1" key="$2" payload="$3"
  curl -fsS -X POST -H "Content-Type: application/json" -H "X-Api-Key: $key" --data "$payload" "$url"
}

wait_http() {
  local url="$1" max="${2:-60}"
  for _ in $(seq 1 "$max"); do
    curl -fsS "$url" >/dev/null 2>&1 && return 0
    sleep 3
  done
  return 1
}

arr_key_from_xml() {
  local file="$1"
  if [[ ! -f "$file" ]]; then return 1; fi
  sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$file" | head -n1
}

safe_jq_set_field_by_name() {
  # stdin: schema object with .fields[], args: field label/name value
  local wanted="$1" value="$2"
  jq --arg wanted "$wanted" --arg value "$value" '
    .fields |= map(
      if ((.name // .label // "") | ascii_downcase) == ($wanted | ascii_downcase)
      then .value = $value else . end
    )
  '
}
