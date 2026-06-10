#!/usr/bin/env bash
set -Eeuo pipefail
export TERM=xterm
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "arr-integrations"

USERS_ENV="/root/homelab-secrets/users.env"
VM102="192.168.50.102"; VM106="192.168.50.106"
QBIT_URL="http://192.168.50.102:8080"
SONARR_URL="http://192.168.50.102:8989"
RADARR_URL="http://192.168.50.102:7878"
PROWLARR_URL="http://192.168.50.102:9696"
LIDARR_URL="http://192.168.50.106:8686"
FLARESOLVERR_URL="http://flaresolverr:8191/"

[[ -f "$USERS_ENV" ]] || { echo "❌ $USERS_ENV bulunamadı."; exit 1; }
set -a; source "$USERS_ENV"; set +a
SSH_USER="${BACMASTER_USER:-bacmaster}"; SSH_PASS="${BACMASTER_PASS:-}"
SERVICE_USER="${BACMASTER_USER:-bacmaster}"; SERVICE_PASS="${BACMASTER_PASS:-}"
[[ -n "$SSH_PASS" && -n "$SERVICE_PASS" ]] || { echo "❌ BACMASTER_PASS users.env içinde bulunamadı."; exit 1; }

apt update
apt install -y sshpass curl jq
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8)

run_ssh(){ local ip="$1" tmp; tmp="$(mktemp)"; cat > "$tmp"; sshpass -p "$SSH_PASS" scp "${SSH_OPTS[@]}" "$tmp" "$SSH_USER@$ip:/tmp/homelab-arr-run.sh" >/dev/null; sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$ip" "printf '%s\n' '$SSH_PASS' | sudo -S -p '' bash /tmp/homelab-arr-run.sh"; rm -f "$tmp"; }
remote_api_key(){ local ip="$1" config="$2"; sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$ip" "printf '%s\n' '$SSH_PASS' | sudo -S -p '' sh -c \"sed -n 's:.*<ApiKey>\\(.*\\)</ApiKey>.*:\\1:p' '$config' | head -n1\"" 2>/dev/null | tr -d '\r' || true; }

api(){ local method="$1" url="$2" key="$3" path="$4" version="$5" payload="${6:-}" out="${7:-/tmp/api.out}"; local full="$url/api/$version$path"; if [[ "$method" == "GET" ]]; then curl -sS -o "$out" -w '%{http_code}' -H "X-Api-Key: $key" "$full"; elif [[ "$method" == "DELETE" ]]; then curl -sS -o "$out" -w '%{http_code}' -X DELETE -H "X-Api-Key: $key" "$full"; else curl -sS -o "$out" -w '%{http_code}' -X "$method" -H "X-Api-Key: $key" -H 'Content-Type: application/json' --data "$payload" "$full"; fi; }
api_get(){ local url="$1" key="$2" path="$3" version="$4"; curl -fsS -H "X-Api-Key: $key" "$url/api/$version$path"; }

wait_api(){ local name="$1" url="$2" key="$3" version="$4"; echo "⏳ $name API bekleniyor..."; for _ in {1..60}; do [[ "$(api GET "$url" "$key" "/system/status" "$version" /tmp/${name}.status 2>/dev/null || true)" == 200 ]] && { echo "✅ $name API hazır."; return 0; }; sleep 2; done; echo "⚠️ $name API erişilemedi: $url"; return 1; }

check_mount_vm102(){ echo; echo "🧪 VM102 /mnt/media mount ve yazma testi..."; run_ssh "$VM102" <<'EOS'
set -euo pipefail
mountpoint -q /mnt/media || mount -a || true
mountpoint -q /mnt/media || { echo "❌ /mnt/media mount değil."; exit 1; }
for dir in /mnt/media/downloads /mnt/media/movies /mnt/media/series; do mkdir -p "$dir"; testfile="$dir/.homelab-write-test"; echo test > "$testfile"; rm -f "$testfile"; echo "✅ Yazma testi başarılı: $dir"; done
EOS
}
check_mount_vm106(){ echo; echo "🧪 VM106 /mnt/media mount ve yazma testi..."; run_ssh "$VM106" <<'EOS'
set -euo pipefail
mountpoint -q /mnt/media || mount -a || true
mountpoint -q /mnt/media || { echo "❌ /mnt/media mount değil."; exit 1; }
for dir in /mnt/media/music /mnt/media/downloads; do mkdir -p "$dir"; testfile="$dir/.homelab-write-test"; echo test > "$testfile"; rm -f "$testfile"; echo "✅ Yazma testi başarılı: $dir"; done
EOS
}

qb_login(){ rm -f /tmp/qbit.cookies; curl -fsS -i -c /tmp/qbit.cookies --data-urlencode "username=$1" --data-urlencode "password=$2" "$QBIT_URL/api/v2/auth/login" | grep -qi Ok; }
configure_qbittorrent(){ echo; echo "🧲 qBittorrent kategori ve tercih ayarları..."; qb_login "$SERVICE_USER" "$SERVICE_PASS" || { echo "⚠️ qBittorrent login başarısız: $SERVICE_USER"; return 0; }; curl -fsS -b /tmp/qbit.cookies --data-urlencode 'json={"save_path":"/downloads/","temp_path_enabled":false,"create_subfolder_enabled":true}' "$QBIT_URL/api/v2/app/setPreferences" >/dev/null || true; for c in sonarr radarr lidarr; do curl -fsS -b /tmp/qbit.cookies --data-urlencode "category=$c" --data-urlencode "savePath=/downloads/$c" "$QBIT_URL/api/v2/torrents/createCategory" >/dev/null || true; done; echo "✅ qBittorrent kategorileri hazır: sonarr, radarr, lidarr"; }

add_root_folder_v3(){ local app="$1" url="$2" key="$3" path="$4"; echo; echo "📁 $app root folder kontrolü: $path"; existing="$(api_get "$url" "$key" /rootfolder v3 2>/dev/null || echo '[]')"; echo "$existing" | jq -e --arg path "$path" '.[] | select(.path==$path)' >/dev/null 2>&1 && { echo "✅ $app root folder zaten var."; return 0; }; payload="$(jq -n --arg path "$path" '{path:$path}')"; http="$(api POST "$url" "$key" /rootfolder v3 "$payload" /tmp/${app}-root.out || true)"; if [[ "$http" =~ ^20[01]$ ]]; then echo "✅ $app root folder eklendi."; else echo "⚠️ $app root folder eklenemedi. HTTP=$http"; cat /tmp/${app}-root.out | jq . 2>/dev/null || cat /tmp/${app}-root.out; fi; }

lidarr_profile_id(){ local endpoint="$1" name="${2:-Standard}"; api_get "$LIDARR_URL" "$LIDARR_KEY" "$endpoint" v1 | jq -r --arg name "$name" '.[] | select(.name==$name) | .id' | head -n1; }
restart_lidarr(){ sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$VM106" "cd /opt/homelab/lidarr && docker compose restart lidarr >/dev/null" || true; sleep 20; wait_api Lidarr "$LIDARR_URL" "$LIDARR_KEY" v1 || true; }
add_root_folder_lidarr(){ echo; echo "📁 Lidarr root folder kontrolü: /media/music"; existing="$(api_get "$LIDARR_URL" "$LIDARR_KEY" /rootfolder v1 2>/dev/null || echo '[]')"; echo "$existing" | jq -e '.[] | select(.path=="/media/music")' >/dev/null 2>&1 && { echo "✅ Lidarr root folder zaten var."; return 0; }; meta="$(lidarr_profile_id /metadataprofile Standard || true)"; qual="$(lidarr_profile_id /qualityprofile Standard || true)"; meta="${meta:-1}"; qual="${qual:-3}"; payload="$(jq -n --arg path /media/music --arg name Music --argjson meta "$meta" --argjson qual "$qual" '{path:$path,name:$name,defaultMetadataProfileId:$meta,defaultQualityProfileId:$qual}')"; for i in {1..8}; do echo "  Lidarr rootfolder POST try $i..."; http="$(api POST "$LIDARR_URL" "$LIDARR_KEY" /rootfolder v1 "$payload" /tmp/lidarr-root.out || true)"; if [[ "$http" =~ ^20[01]$ ]]; then echo "✅ Lidarr root folder eklendi."; return 0; fi; if grep -qi 'database is locked' /tmp/lidarr-root.out 2>/dev/null; then echo "⚠️ Lidarr DB locked; restart/wait/backoff..."; restart_lidarr; sleep $((i*5)); continue; fi; echo "⚠️ Lidarr root folder eklenemedi. HTTP=$http"; cat /tmp/lidarr-root.out | jq . 2>/dev/null || cat /tmp/lidarr-root.out; return 0; done; echo "⚠️ Lidarr root folder retry limit aşıldı."; }

delete_client(){ local app="$1" url="$2" key="$3" version="$4" name="qBittorrent"; existing="$(api_get "$url" "$key" /downloadclient "$version" 2>/dev/null || echo '[]')"; ids="$(echo "$existing" | jq -r --arg name "$name" '.[] | select(.name==$name) | .id' || true)"; while read -r id; do [[ -n "$id" && "$id" != null ]] || continue; echo "🧹 $app eski download client siliniyor: ID $id"; api DELETE "$url" "$key" "/downloadclient/$id" "$version" '' /tmp/delete.out >/dev/null || true; done <<<"$ids"; }
post_client(){ local app="$1" url="$2" key="$3" version="$4" payload="$5"; http="$(api POST "$url" "$key" /downloadclient "$version" "$payload" /tmp/${app}-qbit.out || true)"; if [[ "$http" =~ ^20[01]$ ]]; then echo "✅ $app qBittorrent bağlantısı eklendi."; else echo "⚠️ $app qBittorrent eklenemedi. HTTP=$http"; cat /tmp/${app}-qbit.out | jq 'del(.fields[]?.value? | select(type=="string" and length>12))' 2>/dev/null || cat /tmp/${app}-qbit.out; fi; }
add_qbit_sonarr(){ echo; echo "📺 Sonarr → qBittorrent bağlantısı..."; delete_client Sonarr "$SONARR_URL" "$SONARR_KEY" v3; payload="$(jq -n --arg user "$SERVICE_USER" --arg pass "$SERVICE_PASS" '{enable:true,protocol:"torrent",priority:1,removeCompletedDownloads:true,removeFailedDownloads:true,name:"qBittorrent",implementation:"QBittorrent",configContract:"QBittorrentSettings",fields:[{name:"host",value:"192.168.50.102"},{name:"port",value:8080},{name:"useSsl",value:false},{name:"urlBase",value:""},{name:"username",value:$user},{name:"password",value:$pass},{name:"category",value:"sonarr"},{name:"recentTvPriority",value:0},{name:"olderTvPriority",value:0},{name:"initialState",value:0}]}')"; post_client Sonarr "$SONARR_URL" "$SONARR_KEY" v3 "$payload"; }
add_qbit_radarr(){ echo; echo "🎬 Radarr → qBittorrent bağlantısı..."; delete_client Radarr "$RADARR_URL" "$RADARR_KEY" v3; payload="$(jq -n --arg user "$SERVICE_USER" --arg pass "$SERVICE_PASS" '{enable:true,protocol:"torrent",priority:1,removeCompletedDownloads:true,removeFailedDownloads:true,name:"qBittorrent",implementation:"QBittorrent",configContract:"QBittorrentSettings",fields:[{name:"host",value:"192.168.50.102"},{name:"port",value:8080},{name:"useSsl",value:false},{name:"urlBase",value:""},{name:"username",value:$user},{name:"password",value:$pass},{name:"category",value:"radarr"},{name:"recentMoviePriority",value:0},{name:"olderMoviePriority",value:0},{name:"initialState",value:0}]}')"; post_client Radarr "$RADARR_URL" "$RADARR_KEY" v3 "$payload"; }
add_qbit_lidarr(){ echo; echo "🎵 Lidarr → qBittorrent bağlantısı..."; delete_client Lidarr "$LIDARR_URL" "$LIDARR_KEY" v1; payload="$(jq -n --arg user "$SERVICE_USER" --arg pass "$SERVICE_PASS" '{enable:true,protocol:"torrent",priority:1,removeCompletedDownloads:true,removeFailedDownloads:true,name:"qBittorrent",implementation:"QBittorrent",implementationName:"qBittorrent",configContract:"QBittorrentSettings",fields:[{name:"host",value:"192.168.50.102"},{name:"port",value:8080},{name:"useSsl",value:false},{name:"urlBase",value:""},{name:"username",value:$user},{name:"password",value:$pass},{name:"musicCategory",value:"lidarr"},{name:"musicImportedCategory",value:""},{name:"recentMusicPriority",value:0},{name:"olderMusicPriority",value:0},{name:"initialState",value:0},{name:"sequentialOrder",value:false},{name:"firstAndLast",value:false},{name:"contentLayout",value:0}],tags:[]}')"; post_client Lidarr "$LIDARR_URL" "$LIDARR_KEY" v1 "$payload"; }

prowlarr_get_or_create_tag(){ local label="$1"; tag="$(api_get "$PROWLARR_URL" "$PROWLARR_KEY" /tag v1 | jq -r --arg label "$label" '.[] | select(.label==$label) | .id' | head -n1 || true)"; [[ -n "$tag" && "$tag" != null ]] && { echo "$tag"; return; }; http="$(api POST "$PROWLARR_URL" "$PROWLARR_KEY" /tag v1 "$(jq -n --arg label "$label" '{label:$label}')" /tmp/tag.out || true)"; [[ "$http" =~ ^20[01]$ ]] && jq -r '.id // empty' /tmp/tag.out; }
configure_flaresolverr(){ echo; echo "🔥 Prowlarr → FlareSolverr proxy ayarlanıyor..."; tag_id="$(prowlarr_get_or_create_tag flaresolverr || true)"; tag_json="[]"; [[ -n "$tag_id" && "$tag_id" != null ]] && tag_json="[$tag_id]"; existing="$(api_get "$PROWLARR_URL" "$PROWLARR_KEY" /indexerproxy v1 2>/dev/null || echo '[]')"; echo "$existing" | jq -r '.[] | select(.name=="FlareSolverr" or .implementation=="FlareSolverr") | .id' | while read -r id; do [[ -n "$id" && "$id" != null ]] && api DELETE "$PROWLARR_URL" "$PROWLARR_KEY" "/indexerproxy/$id" v1 '' /tmp/delete-proxy.out >/dev/null || true; done; payload="$(jq -n --arg host "$FLARESOLVERR_URL" --argjson tags "$tag_json" '{name:"FlareSolverr",implementation:"FlareSolverr",configContract:"FlareSolverrSettings",tags:$tags,fields:[{name:"host",value:$host}]}')"; http="$(api POST "$PROWLARR_URL" "$PROWLARR_KEY" /indexerproxy v1 "$payload" /tmp/proxy.out || true)"; [[ "$http" =~ ^20[01]$ ]] && echo "✅ FlareSolverr proxy eklendi." || { echo "⚠️ FlareSolverr proxy eklenemedi HTTP=$http"; cat /tmp/proxy.out; }; }

prowlarr_delete_app(){ local name="$1"; apps="$(api_get "$PROWLARR_URL" "$PROWLARR_KEY" /applications v1 2>/dev/null || echo '[]')"; echo "$apps" | jq -r --arg name "$name" '.[] | select(.name==$name) | .id' | while read -r id; do [[ -n "$id" && "$id" != null ]] && api DELETE "$PROWLARR_URL" "$PROWLARR_KEY" "/applications/$id" v1 '' /tmp/app-del.out >/dev/null || true; done; }
add_prowlarr_app(){ local name="$1" baseUrl="$2" apiKey="$3" impl="$4" categories="$5" extra="${6:-}"; echo; echo "🔗 Prowlarr → $name app sync..."; prowlarr_delete_app "$name"; payload="$(jq -n --arg name "$name" --arg prowlarrUrl "$PROWLARR_URL" --arg baseUrl "$baseUrl" --arg apiKey "$apiKey" --arg impl "$impl" --argjson cats "$categories" --argjson extra "${extra:-[]}" '{name:$name,syncLevel:"fullSync",implementation:$impl,configContract:($impl+"Settings"),fields:([{name:"prowlarrUrl",value:$prowlarrUrl},{name:"baseUrl",value:$baseUrl},{name:"apiKey",value:$apiKey},{name:"syncCategories",value:$cats}] + $extra)}')"; http="$(api POST "$PROWLARR_URL" "$PROWLARR_KEY" /applications v1 "$payload" /tmp/prowlarr-${name}.out || true)"; [[ "$http" =~ ^20[01]$ ]] && echo "✅ Prowlarr $name app eklendi." || { echo "⚠️ Prowlarr $name app eklenemedi HTTP=$http"; cat /tmp/prowlarr-${name}.out | jq . 2>/dev/null || cat /tmp/prowlarr-${name}.out; }; }

trigger_and_validate_sync(){ echo; echo "🔄 Prowlarr indexer sync tetikleniyor..."; http="$(api POST "$PROWLARR_URL" "$PROWLARR_KEY" /command v1 '{"name":"ApplicationIndexerSync"}' /tmp/prowlarr-sync.json || true)"; if [[ ! "$http" =~ ^20[01]$ ]]; then echo "⚠️ Prowlarr sync komutu başarısız HTTP=$http"; cat /tmp/prowlarr-sync.json; return 0; fi; id="$(jq -r '.id // empty' /tmp/prowlarr-sync.json)"; echo "✅ Sync komutu başladı: id=$id"; for _ in {1..30}; do [[ -n "$id" ]] || break; api GET "$PROWLARR_URL" "$PROWLARR_KEY" "/command/$id" v1 /tmp/prowlarr-cmd.json >/tmp/http.tmp || true; status="$(jq -r '.status // empty' /tmp/prowlarr-cmd.json 2>/dev/null || true)"; [[ "$status" == completed || "$status" == failed ]] && break; sleep 5; done; [[ -f /tmp/prowlarr-cmd.json ]] && cat /tmp/prowlarr-cmd.json | jq '{id,name,status,message,started,ended,duration}' 2>/dev/null || true; echo; echo "🔎 App indexer doğrulaması:"; for spec in "Sonarr|$SONARR_URL|$SONARR_KEY|v3" "Radarr|$RADARR_URL|$RADARR_KEY|v3" "Lidarr|$LIDARR_URL|$LIDARR_KEY|v1"; do IFS='|' read -r app url key ver <<<"$spec"; list="$(api_get "$url" "$key" /indexer "$ver" 2>/dev/null || echo '[]')"; count="$(echo "$list" | jq 'length' 2>/dev/null || echo 0)"; if [[ "$count" -gt 0 ]]; then echo "✅ $app indexer sayısı: $count"; else echo "⚠️ $app indexer listesi boş. Muhtemel sebep: Prowlarr indexer kategori/test validation (No Results in configured categories)."; fi; done; }

print_summary(){ echo; echo "✅ 06-configure-arr-integrations.sh tamamlandı."; echo "Not: Lidarr/Radarr/Sonarr indexer sync kategori validation nedeniyle WARN verebilir; run-all durmaz."; }

check_mount_vm102
check_mount_vm106

echo; echo "🔑 API keyler okunuyor..."
SONARR_KEY="$(remote_api_key "$VM102" "/opt/homelab/arr/config/sonarr/config.xml")"
RADARR_KEY="$(remote_api_key "$VM102" "/opt/homelab/arr/config/radarr/config.xml")"
PROWLARR_KEY="$(remote_api_key "$VM102" "/opt/homelab/arr/config/prowlarr/config.xml")"
LIDARR_KEY="$(remote_api_key "$VM106" "/opt/homelab/lidarr/config/lidarr/config.xml")"
[[ -n "$SONARR_KEY" ]] && echo "✅ Sonarr API key bulundu." || echo "❌ Sonarr API key yok."
[[ -n "$RADARR_KEY" ]] && echo "✅ Radarr API key bulundu." || echo "❌ Radarr API key yok."
[[ -n "$PROWLARR_KEY" ]] && echo "✅ Prowlarr API key bulundu." || echo "❌ Prowlarr API key yok."
[[ -n "$LIDARR_KEY" ]] && echo "✅ Lidarr API key bulundu." || echo "❌ Lidarr API key yok."
[[ -n "$SONARR_KEY" && -n "$RADARR_KEY" && -n "$PROWLARR_KEY" && -n "$LIDARR_KEY" ]] || { echo "❌ Eksik API key var."; exit 1; }

wait_api Sonarr "$SONARR_URL" "$SONARR_KEY" v3 || true
wait_api Radarr "$RADARR_URL" "$RADARR_KEY" v3 || true
wait_api Prowlarr "$PROWLARR_URL" "$PROWLARR_KEY" v1 || true
wait_api Lidarr "$LIDARR_URL" "$LIDARR_KEY" v1 || true

configure_qbittorrent
add_root_folder_v3 Sonarr "$SONARR_URL" "$SONARR_KEY" /media/series
add_root_folder_v3 Radarr "$RADARR_URL" "$RADARR_KEY" /media/movies
add_root_folder_lidarr
add_qbit_sonarr
add_qbit_radarr
add_qbit_lidarr
configure_flaresolverr
add_prowlarr_app Sonarr "$SONARR_URL" "$SONARR_KEY" Sonarr '[5000,5010,5020,5030,5040,5045,5050,5060,5070,5080]' '[{"name":"animeSyncCategories","value":[5070]},{"name":"syncAnimeStandardFormatSearch","value":true}]'
add_prowlarr_app Radarr "$RADARR_URL" "$RADARR_KEY" Radarr '[2000,2010,2020,2030,2040,2045,2050,2060,2070,2080]'
add_prowlarr_app Lidarr "$LIDARR_URL" "$LIDARR_KEY" Lidarr '[3000,3010,3020,3030,3040,3050,3060]'
trigger_and_validate_sync
print_summary
