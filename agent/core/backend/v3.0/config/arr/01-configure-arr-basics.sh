#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "arr-configure-basics"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

# This script intentionally runs inside the target VMs, close to the containers.
# It sets common root folders and qBittorrent download client using official *arr APIs where available.

ARR_USER="${ARR_USER:-${BACMASTER_USER:-bacmaster}}"
ARR_PASS="${ARR_PASS:-${BACMASTER_PASS:-}}"

make_remote_arr_script() {
cat <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
need(){ command -v "$1" >/dev/null || { echo "missing $1"; exit 1; }; }
need curl; need jq

api_key(){ sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$1" 2>/dev/null | head -n1; }
wait_url(){ local u="$1"; for _ in $(seq 1 60); do curl -fsS "$u" >/dev/null 2>&1 && return 0; sleep 3; done; return 1; }

add_root_folder(){
  local app="$1" port="$2" key="$3" path="$4"
  [[ -n "$key" ]] || { echo "⚠️ $app API key yok"; return 0; }
  wait_url "http://127.0.0.1:$port/ping" || { echo "⚠️ $app ping yok"; return 0; }
  if curl -fsS -H "X-Api-Key: $key" "http://127.0.0.1:$port/api/v3/rootfolder" | jq -e --arg p "$path" '.[] | select(.path==$p)' >/dev/null; then
    echo "✅ $app root folder zaten var: $path"
  else
    curl -fsS -X POST -H "X-Api-Key: $key" -H "Content-Type: application/json" \
      --data "$(jq -n --arg path "$path" '{path:$path}')" \
      "http://127.0.0.1:$port/api/v3/rootfolder" >/dev/null \
      && echo "✅ $app root folder eklendi: $path" || echo "⚠️ $app root folder eklenemedi"
  fi
}

add_qbit_client(){
  local app="$1" port="$2" key="$3" category="$4"
  [[ -n "$key" ]] || return 0
  wait_url "http://127.0.0.1:$port/ping" || return 0
  if curl -fsS -H "X-Api-Key: $key" "http://127.0.0.1:$port/api/v3/downloadclient" | jq -e '.[] | select(.name=="qBittorrent")' >/dev/null; then
    echo "✅ $app qBittorrent zaten var"
    return 0
  fi

  schema="$(curl -fsS -H "X-Api-Key: $key" "http://127.0.0.1:$port/api/v3/downloadclient/schema" \
    | jq '[.[] | select(.implementation=="QBittorrent")] | .[0]')"
  [[ "$schema" != "null" && -n "$schema" ]] || { echo "⚠️ $app QBittorrent schema bulunamadı"; return 0; }

  payload="$(echo "$schema" | jq \
    --arg cat "$category" \
    '.name="qBittorrent"
     | .enable=true
     | .priority=1
     | .fields |= map(
        if .name=="host" then .value="qbittorrent"
        elif .name=="port" then .value=8080
        elif .name=="useSsl" then .value=false
        elif .name=="urlBase" then .value=""
        elif .name=="username" then .value=""
        elif .name=="password" then .value=""
        elif .name=="tvCategory" then .value=$cat
        elif .name=="movieCategory" then .value=$cat
        elif .name=="musicCategory" then .value=$cat
        elif .name=="recentTvPriority" then .value=0
        elif .name=="olderTvPriority" then .value=0
        else . end
      )')"

  curl -fsS -X POST -H "X-Api-Key: $key" -H "Content-Type: application/json" \
    --data "$payload" "http://127.0.0.1:$port/api/v3/downloadclient" >/dev/null \
    && echo "✅ $app qBittorrent eklendi" || echo "⚠️ $app qBittorrent eklenemedi"
}

SONARR_KEY="$(api_key /opt/homelab/arr/config/sonarr/config.xml)"
RADARR_KEY="$(api_key /opt/homelab/arr/config/radarr/config.xml)"

add_root_folder Sonarr 8989 "$SONARR_KEY" /media/series
add_root_folder Radarr 7878 "$RADARR_KEY" /media/movies
add_qbit_client Sonarr 8989 "$SONARR_KEY" sonarr
add_qbit_client Radarr 7878 "$RADARR_KEY" radarr
EOS
}

TMP="$(mktemp -d)"
make_remote_arr_script > "$TMP/configure-arr-vm102.sh"
chmod +x "$TMP/configure-arr-vm102.sh"
rscp "$TMP/configure-arr-vm102.sh" 102 /tmp/configure-arr-vm102.sh
rssh 102 "sudo bash /tmp/configure-arr-vm102.sh"

cat > "$TMP/configure-lidarr-vm106.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
command -v curl >/dev/null || exit 0
command -v jq >/dev/null || exit 0
key="$(sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' /opt/homelab/lidarr/config/lidarr/config.xml 2>/dev/null | head -n1 || true)"
[[ -n "$key" ]] || { echo "⚠️ Lidarr API key yok"; exit 0; }
for _ in $(seq 1 60); do curl -fsS http://127.0.0.1:8686/ping >/dev/null 2>&1 && break; sleep 3; done
if ! curl -fsS -H "X-Api-Key: $key" http://127.0.0.1:8686/api/v1/rootfolder | jq -e '.[] | select(.path=="/media/music")' >/dev/null; then
  curl -fsS -X POST -H "X-Api-Key: $key" -H "Content-Type: application/json" \
    --data '{"path":"/media/music"}' http://127.0.0.1:8686/api/v1/rootfolder >/dev/null || true
fi
echo "✅ Lidarr basic config denendi"
EOS
chmod +x "$TMP/configure-lidarr-vm106.sh"
rscp "$TMP/configure-lidarr-vm106.sh" 106 /tmp/configure-lidarr-vm106.sh
rssh 106 "sudo bash /tmp/configure-lidarr-vm106.sh"
rm -rf "$TMP"
