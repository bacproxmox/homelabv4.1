#!/usr/bin/env bash
set -euo pipefail

# Homelab v2.4.7 - TrueNAS post-install helper
# Integrated repo version: reads truenas_admin SSH password from /root/homelab-secrets/truenas-login.env.
# Runs on Proxmox host (root@192.168.50.100)
# Flow:
#   - Fix VM101 boot order / remove installer ISO
#   - Prefer fixed DHCP reservation IP 192.168.50.101
#   - Ask user to enable SSH in TrueNAS WebUI
#   - SSH as truenas_admin
#   - Import tank/private using confirmed TrueNAS middleware syntax WITHOUT -job
#   - Create TrueNAS API key and copy truenas-api.env to /root/homelab-secrets
#   - Set final network/DNS and reboot TrueNAS

SECRETS_DIR="${SECRETS_DIR:-/root/homelab-secrets}"
LOGIN_ENV="${LOGIN_ENV:-${SECRETS_DIR}/truenas-login.env}"

if [[ ! -f "$LOGIN_ENV" ]]; then
  echo "❌ Eksik dosya: $LOGIN_ENV"
  echo "Önce Install Menu -> 1) Bootstrap secrets/env çalıştır; truenas_admin şifresi orada kaydedilecek."
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$LOGIN_ENV"
set +a

VMID="${TRUENAS_VMID:-${VMID:-101}}"
TRUENAS_USER="${TRUENAS_SSH_USER:-${TRUENAS_USER:-truenas_admin}}"
TRUENAS_PASS="${TRUENAS_SSH_PASS:-${TRUENAS_PASS:-}}"
FINAL_IP="${TRUENAS_FINAL_IP:-${TRUENAS_HOST:-${FINAL_IP:-192.168.50.101}}}"
SUBNET="${SUBNET:-192.168.50.0/24}"
GATEWAY="${TRUENAS_GATEWAY:-${GATEWAY:-192.168.50.1}}"
DNS1="${TRUENAS_DNS1:-${DNS1:-192.168.50.1}}"
DNS2="${TRUENAS_DNS2:-${DNS2:-192.168.50.1}}"
DNS3="${TRUENAS_DNS3:-${DNS3:-1.1.1.1}}"
CIDR="${CIDR:-24}"
OUT_ENV="${OUT_ENV:-${SECRETS_DIR}/truenas-api.env}"
LEGACY_ENV="${LEGACY_ENV:-${SECRETS_DIR}/truenas.env}"
LOG_DIR="${LOG_DIR:-/root/homelab-logs}"
LOG="${LOG_DIR}/truenas-postinstall-v2314-$(date +%Y%m%d-%H%M%S).log"

if [[ -z "$TRUENAS_PASS" ]]; then
  echo "❌ TRUENAS_SSH_PASS boş. $LOGIN_ENV dosyasını kontrol et."
  exit 1
fi

# Confirmed current pool GUIDs from this TrueNAS system / WebUI.
TANK_GUID_DEFAULT="14345028207300573632"
PRIVATE_GUID_DEFAULT="728378451231267446"
TRUENAS_PRIVATE_REQUIRED="${TRUENAS_PRIVATE_REQUIRED:-0}"

mkdir -p "$LOG_DIR" "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"
# Fresh postinstall always produces a new API key. Remove stale/imported API envs before starting.
rm -f "$OUT_ENV" "$LEGACY_ENV" 2>/dev/null || true
exec > >(tee -a "$LOG") 2>&1

say() { printf '%s\n' "$*"; }
ok() { say "✅ $*"; }
warn() { say "⚠️ $*"; }
fail() { say "❌ $*"; exit 1; }

say "============================================================"
say " Homelab v2.4.7 - TrueNAS post-install importfix v8"
say "============================================================"
say "Log: $LOG"
say

say "[1/9] Gerekli paketler kontrol ediliyor..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null
apt-get install -y sshpass arp-scan nmap >/dev/null
ok "Paketler hazır."
say

say "[2/9] VM${VMID} kurulum ISO/CD kaldırma + boot order düzeltme..."
if [[ "${TRUENAS_SKIP_BOOT_FIX:-0}" == "1" ]]; then
  ok "TRUENAS_SKIP_BOOT_FIX=1; guided checkpoint bu adımı zaten yaptığı için boot-fix/reboot atlandı."
else
  if ! qm status "$VMID" >/dev/null 2>&1; then
    fail "VM${VMID} bulunamadı. Önce TrueNAS VM oluşturulmalı."
  fi

  if qm status "$VMID" | grep -q "status: running"; then
    say "VM çalışıyor; güvenli durduruluyor..."
    qm stop "$VMID" || true
    sleep 5
  fi
  say "CD/DVD kaldırılıyor: qm set ${VMID} --ide2 none"
  qm set "$VMID" --ide2 none || true
  say "Boot order ayarlanıyor: scsi0"
  qm set "$VMID" --boot order=scsi0 || true
  say "VM başlatılıyor..."
  qm start "$VMID" || true
  say "TrueNAS boot için 60 saniye bekleniyor..."
  sleep 60
  ok "VM boot beklemesi tamam."
fi
say

say "[3/9] VM${VMID} MAC/bridge bilgisi okunuyor..."
TRUENAS_MAC="$(qm config "$VMID" | sed -nE 's/^net[0-9]+:.*=(([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}).*/\1/p' | head -n1 | tr '[:upper:]' '[:lower:]')"
TRUENAS_BRIDGE="$(qm config "$VMID" | sed -nE 's/^net[0-9]+:.*bridge=([^, ]+).*/\1/p' | head -n1)"
TRUENAS_BRIDGE="${TRUENAS_BRIDGE:-vmbr0}"
[ -n "$TRUENAS_MAC" ] || fail "VM${VMID} MAC adresi okunamadı."
ok "MAC: $TRUENAS_MAC"
ok "Bridge: $TRUENAS_BRIDGE"
say

mac_for_ip() {
  local ip="$1"
  ping -c1 -W1 "$ip" >/dev/null 2>&1 || true
  ip neigh show "$ip" 2>/dev/null | awk '{print tolower($5)}' | head -n1
}

check_final_ip_once() {
  if ! ping -c1 -W1 "$FINAL_IP" >/dev/null 2>&1; then
    return 1
  fi
  local mac
  mac="$(mac_for_ip "$FINAL_IP" || true)"
  if [ -n "$mac" ] && [ "$mac" != "$TRUENAS_MAC" ]; then
    fail "$FINAL_IP erişilebilir ama MAC farklı. Beklenen=$TRUENAS_MAC Bulunan=$mac"
  fi
  if [ -n "$mac" ]; then
    ok "$FINAL_IP erişilebilir ve MAC doğrulandı: $mac"
  else
    warn "$FINAL_IP ping veriyor ama MAC okunamadı; yine de bu IP ile devam edilecek."
  fi
  return 0
}

find_ip_by_mac() {
  local mac="$1"
  local subnet="$2"
  local bridge="$3"
  ip neigh flush all >/dev/null 2>&1 || true
  nmap -sn "$subnet" >/dev/null 2>&1 || true

  local found
  found="$(ip neigh show | awk -v mac="$mac" 'tolower($5)==mac && $1 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ {print $1; exit}')"
  if [ -n "$found" ]; then
    echo "$found"
    return 0
  fi

  found="$(arp-scan -I "$bridge" "$subnet" 2>/dev/null | awk -v mac="$mac" 'tolower($2)==mac && $1 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ {print $1; exit}')"
  if [ -n "$found" ]; then
    echo "$found"
    return 0
  fi

  return 1
}

say "[4/9] TrueNAS IP kontrolü / gerekirse DHCP keşfi..."
say "Final IP: $FINAL_IP"
say "Subnet:   $SUBNET"
say "MAC:      $TRUENAS_MAC"
say
say "Ön kontrol: $FINAL_IP erişilebilir mi?"

TRUENAS_IP=""
if check_final_ip_once; then
  TRUENAS_IP="$FINAL_IP"
  ok "Router DHCP reservation çalışıyor; ağ taraması atlandı."
else
  warn "$FINAL_IP ilk kontrolde erişilebilir değil. 3 kez daha 10 saniye arayla denenecek."
  for attempt in 1 2 3; do
    say "Ek kontrol ${attempt}/3: 10 saniye bekleniyor..."
    sleep 10
    if check_final_ip_once; then
      TRUENAS_IP="$FINAL_IP"
      ok "TrueNAS $FINAL_IP üzerinde bulundu."
      break
    fi
  done
fi

if [ -z "$TRUENAS_IP" ]; then
  warn "$FINAL_IP erişilemedi. DHCP IP, VM MAC adresinden aranıyor..."
  for i in $(seq 1 12); do
    say "Ağ taraması ${i}/12..."
    TRUENAS_IP="$(find_ip_by_mac "$TRUENAS_MAC" "$SUBNET" "$TRUENAS_BRIDGE" || true)"
    if [ -n "$TRUENAS_IP" ]; then
      break
    fi
    sleep 5
  done
fi

[ -n "$TRUENAS_IP" ] || fail "TrueNAS IPv4 adresi bulunamadı."
ok "TrueNAS kullanılacak IP: $TRUENAS_IP"
say
say "TrueNAS WebUI:"
say "  http://${TRUENAS_IP}"
say

say "[5/9] SSH açma bekleniyor..."
if [[ "${TRUENAS_SSH_READY_ASSUMED:-0}" == "1" ]]; then
  ok "Üst pipeline SSH hazır doğrulaması yaptığı için manuel SSH prompt'u atlandı."
else
  say
  say "Şimdi tarayıcıdan TrueNAS WebUI'ye gir:"
  say "  http://${TRUENAS_IP}"
  say
  say "Sonra TrueNAS içinde SSH servisini aç:"
  say "  System Settings / Services > SSH > Edit"
  say "  - Allow Password Authentication: ON"
  say "  - Password Login Groups: builtin_administrators veya truenas_admin'in admin grubu"
  say "  - Save"
  say "  - SSH Start"
  say "  - İstersen 'Start Automatically' de açık kalsın"
  say
  say "Not: Sadece SSH Running yapmak yetmeyebilir; Password Login Groups boş kalırsa"
  say "      TrueNAS 'Permission denied (publickey)' döndürebilir."
  say
  while true; do
    read -r -p "SSH'i açtıysan devam etmek için 'y' yazıp ENTER'a bas. IP kontrolünü tekrar yapmak için 'ara', çıkmak için 'q': " ans
    case "$ans" in
      y|Y) break ;;
      ara|ARA)
        if check_final_ip_once; then TRUENAS_IP="$FINAL_IP"; fi
        say "Kullanılacak IP: $TRUENAS_IP"
        ;;
      q|Q) fail "Kullanıcı iptal etti." ;;
      *) say "Lütfen y / ara / q yaz." ;;
    esac
  done
fi
say

say "[6/9] TrueNAS SSH bağlantısı test ediliyor..."
say "Kullanıcı: $TRUENAS_USER"
say "Şifre: $LOGIN_ENV dosyasından okundu; ekrana yazdırılmayacak."
say

refresh_known_host(){
  local ip="${1:-$TRUENAS_IP}"
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  touch /root/.ssh/known_hosts
  chmod 600 /root/.ssh/known_hosts
  ssh-keygen -f /root/.ssh/known_hosts -R "$ip" >/dev/null 2>&1 || true
  ssh-keygen -f /root/.ssh/known_hosts -R "[$ip]:22" >/dev/null 2>&1 || true
  ssh-keyscan -H "$ip" >> /root/.ssh/known_hosts 2>/dev/null || true
}

refresh_known_host "$TRUENAS_IP"
PASS_B64="$(printf '%s' "$TRUENAS_PASS" | base64 -w0)"

# Inner SSH commands intentionally do NOT allocate a TTY.
# With nested PowerShell -> Proxmox -> TrueNAS sessions, -tt can drop us into
# an interactive TrueNAS shell and echo the heredoc instead of returning cleanly.
SSH_BASE=(
  sshpass -p "$TRUENAS_PASS"
  ssh
  -T
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/root/.ssh/known_hosts
  -o ConnectTimeout=10
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
)
SCP_BASE=(
  sshpass -p "$TRUENAS_PASS"
  scp
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/root/.ssh/known_hosts
  -o ConnectTimeout=10
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
)

if ! "${SSH_BASE[@]}" "${TRUENAS_USER}@${TRUENAS_IP}" "echo SSH_OK && hostname"; then
  fail "SSH bağlantısı başarısız. Password Login Groups / Allow Password Authentication / şifre kontrol edilmeli."
fi
ok "SSH bağlantısı başarılı."
say

say "[7/9] TrueNAS içinde tank/private import + API key oluşturma çalışıyor..."
say "Bu sürüm import için doğrulanmış komutları kullanır: sudo midclt call pool.import_pool '{\"guid\":\"...\"}'"

set +e
"${SSH_BASE[@]}" "${TRUENAS_USER}@${TRUENAS_IP}" \
  "SUDO_PASS_B64='${PASS_B64}' FINAL_IP='${FINAL_IP}' API_USER='${TRUENAS_USER}' TANK_GUID_DEFAULT='${TANK_GUID_DEFAULT}' PRIVATE_GUID_DEFAULT='${PRIVATE_GUID_DEFAULT}' TRUENAS_PRIVATE_REQUIRED='${TRUENAS_PRIVATE_REQUIRED}' bash -s" <<'REMOTE'
set -euo pipefail

SUDO_PASS="$(printf '%s' "$SUDO_PASS_B64" | base64 -d)"
REMOTE_LOG="/tmp/homelab-truenas-v2314-importfix-v8.log"
exec > >(tee -a "$REMOTE_LOG") 2>&1

say() { printf '%s\n' "$*"; }
ok() { say "✅ $*"; }
warn() { say "⚠️ $*"; }
fail() { say "❌ $*"; exit 1; }
srun() { printf '%s\n' "$SUDO_PASS" | sudo -S -p '' "$@"; }
private_required() {
  case "${TRUENAS_PRIVATE_REQUIRED:-0}" in
    1|true|True|TRUE|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

say
say "== TrueNAS remote phase: direct GUID middleware import + API key (non-interactive SSH) =="
say "Log: $REMOTE_LOG"
say

if ! printf '%s\n' "$SUDO_PASS" | sudo -S -p '' true; then
  fail "sudo/root yetkisi alınamadı. truenas_admin admin/sudo yetkili olmalı."
fi
ok "sudo/root yetkisi OK."

is_pool_active() {
  local pool_name="$1"
  srun zpool list -H -o name 2>/dev/null | grep -qx "$pool_name"
}

pool_query_has_name() {
  local pool_name="$1"
  srun midclt call pool.query 2>/dev/null | grep -q '"name"[[:space:]]*:[[:space:]]*"'"$pool_name"'"'
}

extract_guid_from_zpool_import() {
  local pool_name="$1"
  local file="$2"
  awk -v target="$pool_name" '
    /^[[:space:]]*pool:[[:space:]]*/ {
      pool=$2
    }
    pool==target && /^[[:space:]]*id:[[:space:]]*/ {
      print $2
      exit
    }
  ' "$file"
}

extract_job_id() {
  python3 -c '''import json,re,sys
raw=sys.stdin.read().strip()
try:
    data=json.loads(raw)
except Exception:
    m=re.search(r"\b([0-9]{1,10})\b", raw)
    print(m.group(1) if m else "")
    raise SystemExit
if isinstance(data, int):
    print(data)
elif isinstance(data, str) and data.isdigit():
    print(data)
elif isinstance(data, dict):
    for k in ("id","job_id","job"):
        v=data.get(k)
        if isinstance(v, int) or (isinstance(v, str) and v.isdigit()):
            print(v)
            break
'''
}
print_job_result() {
  local job_id="$1"
  [[ -n "$job_id" ]] || return 0
  say "TrueNAS job sonucu alınıyor: $job_id"
  srun midclt call core.get_jobs "[[\"id\",\"=\",${job_id}]]" 2>/tmp/homelab-job-${job_id}.err || true
  cat /tmp/homelab-job-${job_id}.err 2>/dev/null || true
}

wait_pool_import_job() {
  local pool_name="$1" job_id="$2"
  [[ -n "$job_id" ]] || return 0
  local out state err
  for _ in $(seq 1 60); do
    if is_pool_active "$pool_name"; then
      ok "Pool aktif oldu: $pool_name"
      srun zpool status "$pool_name" || true
      return 0
    fi
    out="$(srun midclt call core.get_jobs "[[\"id\",\"=\",${job_id}]]" 2>/tmp/homelab-job-${job_id}.err || true)"
    state="$(JOB_OUT="$out" python3 - <<'PY'
import json, os
raw=os.environ.get('JOB_OUT','').strip()
try:
    data=json.loads(raw)
except Exception:
    print('')
    raise SystemExit
if isinstance(data, list) and data:
    print(str(data[0].get('state','')).upper())
elif isinstance(data, dict):
    print(str(data.get('state','')).upper())
PY
)"
    case "$state" in
      SUCCESS|SUCCESSFUL|FINISHED)
        if is_pool_active "$pool_name"; then
          ok "Pool aktif oldu: $pool_name"
          srun zpool status "$pool_name" || true
          return 0
        fi
        ;;
      FAILED|ABORTED|ERROR)
        err="$(JOB_OUT="$out" python3 - <<'PY'
import json, os
raw=os.environ.get('JOB_OUT','').strip()
try:
    data=json.loads(raw)
except Exception:
    print(raw[:1000])
    raise SystemExit
job=data[0] if isinstance(data, list) and data else data if isinstance(data, dict) else {}
for k in ('error','exception','exc_info','result'):
    v=job.get(k)
    if v:
        print(v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)[:1500])
        break
PY
)"
        fail "TrueNAS import job FAILED: ${pool_name} / job=${job_id} / ${err:-detay yok}"
        ;;
    esac
    sleep 2
  done
  return 1
}

import_pool_direct() {
  local pool_name="$1"
  local default_guid="$2"
  local guid=""
  local discovery_file="/tmp/zpool-import-discovery-${pool_name}.txt"
  local import_out="" job_id="" rc=0

  say
  say "------------------------------------------------------------"
  say "Pool import: ${pool_name}"
  say "------------------------------------------------------------"

  if is_pool_active "$pool_name"; then
    ok "Pool zaten aktif: $pool_name"
    return 0
  fi

  say "Import edilebilir pool keşfi: sudo midclt call pool.import_find"
  srun midclt call pool.import_find || true

  say "zpool import çıktısı alınıyor..."
  srun zpool import > "$discovery_file" 2>&1 || true
  cat "$discovery_file"

  guid="$(extract_guid_from_zpool_import "$pool_name" "$discovery_file" || true)"
  if [ -z "$guid" ]; then
    warn "$pool_name için zpool import çıktısından GUID parse edilemedi; doğrulanmış sabit GUID kullanılacak: $default_guid"
    guid="$default_guid"
  else
    ok "$pool_name GUID bulundu: $guid"
  fi

  say "Middleware import deneniyor: ${pool_name} / GUID=${guid}"
  # Confirmed working on this TrueNAS build. Do NOT use '-job'.
  set +e
  import_out="$(srun midclt call pool.import_pool "{\"guid\":\"${guid}\"}" 2>&1)"
  rc=$?
  set -e
  echo "$import_out"

  if [ "$rc" -ne 0 ]; then
    warn "String GUID payload başarısız oldu; numeric GUID payload deneniyor."
    set +e
    import_out="$(srun midclt call pool.import_pool "{\"guid\":${guid}}" 2>&1)"
    rc=$?
    set -e
    echo "$import_out"
  fi

  if [ "$rc" -ne 0 ]; then
    fail "midclt pool.import_pool başarısız oldu: $pool_name / $guid"
  fi

  job_id="$(printf '%s' "$import_out" | extract_job_id || true)"
  if [ -n "$job_id" ]; then
    say "Import job ID: $job_id"
    wait_pool_import_job "$pool_name" "$job_id" && return 0
    print_job_result "$job_id"
  else
    warn "Import job ID parse edilemedi; pool aktifleşmesi klasik polling ile beklenecek."
  fi

  say "Import job gönderildi. Pool aktifleşmesi bekleniyor..."
  for i in $(seq 1 30); do
    if is_pool_active "$pool_name"; then
      ok "Pool aktif oldu: $pool_name"
      srun zpool status "$pool_name" || true
      return 0
    fi
    sleep 2
  done

  fail "Import job gönderildi ama pool aktif görünmedi: $pool_name"
}
import_pool_direct "tank" "$TANK_GUID_DEFAULT"
if private_required; then
  import_pool_direct "private" "$PRIVATE_GUID_DEFAULT"
else
  warn "TRUENAS_PRIVATE_REQUIRED=0; private pool import atlandı. Bu tank-only kurulumdur."
fi

say
say "Aktif pool listesi:"
srun zpool list || true

if ! is_pool_active "tank"; then
  fail "tank import tamamlanmadı. API/network aşamasına geçilmiyor."
fi
if private_required && ! is_pool_active "private"; then
  fail "private import tamamlanmadı. API/network aşamasına geçilmiyor."
fi

say
say "API key oluşturuluyor..."
API_NAME_BASE="homelabproject"
API_NAME="$API_NAME_BASE"

set +e
API_RESULT="$(srun midclt call api_key.create "{\"name\":\"${API_NAME}\",\"username\":\"${API_USER}\"}" 2>/tmp/api-create.err)"
rc=$?
set -e

if [ "$rc" -ne 0 ] || [ -z "$API_RESULT" ]; then
  warn "${API_NAME} adıyla API key oluşturulamadı; timestamp'li isim deneniyor."
  cat /tmp/api-create.err 2>/dev/null || true
  API_NAME="${API_NAME_BASE}-$(date +%Y%m%d-%H%M%S)"
  API_RESULT="$(srun midclt call api_key.create "{\"name\":\"${API_NAME}\",\"username\":\"${API_USER}\"}")"
fi

API_KEY="$(API_RESULT="$API_RESULT" python3 - <<'PY'
import json, os
raw = os.environ.get("API_RESULT", "").strip()
try:
    data = json.loads(raw)
except Exception:
    print("")
    raise SystemExit
if isinstance(data, str):
    print(data)
    raise SystemExit
if isinstance(data, dict):
    for k in ("key", "api_key", "apikey"):
        if data.get(k):
            print(data[k])
            raise SystemExit
    # Some TrueNAS variants nest output.
    def walk(x):
        if isinstance(x, dict):
            yield x
            for v in x.values():
                yield from walk(v)
        elif isinstance(x, list):
            for i in x:
                yield from walk(i)
    for d in walk(data):
        for k in ("key", "api_key", "apikey"):
            if d.get(k):
                print(d[k])
                raise SystemExit
print("")
PY
)"

[ -n "$API_KEY" ] || fail "API key oluşturuldu ama key yakalanamadı. Raw output loga yazılmadı."

sq() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/"
}

cat >/tmp/truenas-api.env <<ENV
# Homelab TrueNAS API credentials
# Generated on: $(date -Is)

TRUENAS_HOST=${FINAL_IP}
TRUENAS_URL=http://${FINAL_IP}
TRUENAS_API_USER=${API_USER}
TRUENAS_API_KEY=$(sq "$API_KEY")
TRUENAS_API_KEY_NAME=${API_NAME}
ENV
chmod 600 /tmp/truenas-api.env
ok "/tmp/truenas-api.env oluşturuldu. API key ekrana yazdırılmadı."
REMOTE
remote_rc=$?
set -e

if [ "$remote_rc" -ne 0 ]; then
  fail "TrueNAS remote import/API aşaması başarısız oldu. API/network aşamasına geçilmedi."
fi
ok "Remote import/API aşaması tamamlandı."
say

say "[8/9] truenas-api.env Proxmox'a çekiliyor..."
"${SCP_BASE[@]}" "${TRUENAS_USER}@${TRUENAS_IP}:/tmp/truenas-api.env" "$OUT_ENV"
chmod 600 "$OUT_ENV"
ok "Env dosyası alındı: $OUT_ENV"
say "İçerik kontrolü:"
sed -E 's/(TRUENAS_API_KEY=).*/\1***REDACTED***/' "$OUT_ENV"

# Backward-compatible env for older scripts. New code should prefer truenas-api.env.
set -a
# shellcheck disable=SC1090
source "$OUT_ENV"
set +a
{
  echo "# Compatibility file generated from truenas-api.env"
  echo "# Generated on: $(date -Is)"
  echo "TRUENAS_IP=${TRUENAS_HOST:-$FINAL_IP}"
  printf 'TRUENAS_API_KEY=%q\n' "$TRUENAS_API_KEY"
} > "$LEGACY_ENV"
chmod 600 "$LEGACY_ENV"
ok "Compatibility env yazıldı: $LEGACY_ENV"
rm -f "$SECRETS_DIR/.fresh-truenas-api-required" 2>/dev/null || true
ok "Fresh TrueNAS API marker temizlendi."
say

say "[9/9] TrueNAS final network/DNS ayarı ve reboot..."
say "IP:      ${FINAL_IP}/${CIDR}"
say "Gateway: ${GATEWAY}"
say "DNS1:    ${DNS1}"
say "DNS2:    ${DNS2}"
say "DNS3:    ${DNS3}"
say
warn "Bu aşamada TrueNAS SSH/WebUI bağlantısı kopabilir; bu normal."

set +e
"${SSH_BASE[@]}" "${TRUENAS_USER}@${TRUENAS_IP}" \
  "SUDO_PASS_B64='${PASS_B64}' FINAL_IP='${FINAL_IP}' GATEWAY='${GATEWAY}' DNS1='${DNS1}' DNS2='${DNS2}' DNS3='${DNS3}' CIDR='${CIDR}' bash -s" <<'REMOTE'
set -euo pipefail
SUDO_PASS="$(printf '%s' "$SUDO_PASS_B64" | base64 -d)"
srun() { printf '%s\n' "$SUDO_PASS" | sudo -S -p '' "$@"; }

IFACE="$(ip -o -4 route show default 2>/dev/null | awk '{print $5}' | head -n1 || true)"
if [ -z "$IFACE" ]; then
  IFACE="$(ip -o link show | awk -F': ' '$2!="lo"{print $2}' | grep -E '^(eno|ens|enp|eth)' | head -n1 || true)"
fi
[ -n "$IFACE" ] || exit 1

echo "Final network interface: $IFACE"

srun midclt call network.configuration.update "{\"ipv4gateway\":\"${GATEWAY}\",\"nameserver1\":\"${DNS1}\",\"nameserver2\":\"${DNS2}\",\"nameserver3\":\"${DNS3}\"}" || true

srun midclt call interface.update "$IFACE" "{\"ipv4_dhcp\":false,\"aliases\":[{\"type\":\"INET\",\"address\":\"${FINAL_IP}\",\"netmask\":${CIDR}}]}"
srun midclt call interface.commit || true
srun midclt call interface.checkin || true

# Reboot in background so SSH command can return/close safely.
( sleep 3; printf '%s\n' "$SUDO_PASS" | sudo -S -p '' /sbin/shutdown -r now ) >/tmp/homelab-truenas-reboot.log 2>&1 &
echo "Reboot scheduled."
REMOTE
set -e

say
say "TrueNAS reboot/erişim bekleniyor..."
sleep 10
for i in $(seq 1 90); do
  if ping -c1 -W1 "$FINAL_IP" >/dev/null 2>&1; then
    ok "TrueNAS ${FINAL_IP} üzerinde cevap veriyor."
    say
    say "WebUI: http://${FINAL_IP}"
    say "Env:   ${OUT_ENV}"
    say
    ok "Tamamlandı."
    exit 0
  fi
  say "Bekleniyor... ${i}/90"
  sleep 3
done

warn "TrueNAS ${FINAL_IP} üzerinde henüz ping vermedi. Reboot/network değişimi devam ediyor olabilir."
say "WebUI'yi biraz sonra kontrol et: http://${FINAL_IP}"
say "Env dosyası oluştu: ${OUT_ENV}"
exit 0
