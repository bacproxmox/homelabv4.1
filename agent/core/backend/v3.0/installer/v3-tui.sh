#!/usr/bin/env bash
set -Eeuo pipefail

export TERM="${TERM:-xterm}"
export HOMELAB_VERSION="${HOMELAB_VERSION:-3.0}"
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${STATE_DIR:-/root/homelabv3-state}"
STATE_FILE="$STATE_DIR/state.tsv"
LOG_ROOT="${LOG_DIR:-/root/homelab-logs}"
SESSION_FILE="$STATE_DIR/current-session"
SESSION_DIR=""
MASTER_LOG=""
CURRENT_STEP_LOG=""
CURRENT_STEP_ID=""
CURRENT_STEP_TITLE=""
CURRENT_STEP_INDEX="0"

mkdir -p "$STATE_DIR" "$LOG_ROOT"
chmod 700 "$STATE_DIR" "$LOG_ROOT" 2>/dev/null || true

declare -a STEP_IDS=()
declare -a STEP_TITLES=()
declare -a STEP_WEIGHTS=()
declare -a STEP_CRITICAL=()

add_step() {
  STEP_IDS+=("$1")
  STEP_TITLES+=("$2")
  STEP_WEIGHTS+=("$3")
  STEP_CRITICAL+=("$4")
}

# v3.0 intentionally calls the existing v2.4.7 backend scripts as-is.
# Progress is phase/script based, so backend scripts do not need progress hooks.
add_step "secrets"              "Secrets/env bootstrap + optional encrypted import"                 8  yes
add_step "cloudflare_prepare"   "Early Cloudflare Tunnel credential prepare"                       3  no
add_step "hardware_preflight"   "Hardware / SMART / temperature preflight"                         2  no
add_step "proxmox_users"        "Create Proxmox users"                                             4  yes
add_step "storage_normalize"    "Normalize Proxmox local/NVMe storage"                             6  yes
add_step "truenas_checkpoint"   "TrueNAS VM 101 + manual install/WebUI/SSH checkpoint"            12  yes
add_step "truenas_storage"      "Fresh TrueNAS API + storage bootstrap"                            8  yes
add_step "vm102"                "VM102 docker-arr install"                                         4  yes
add_step "vm103"                "VM103 docker-network install"                                     4  yes
add_step "vm104"                "VM104 Bacscloud/Nextcloud install"                                4  yes
add_step "vm105"                "VM105 Home Assistant install"                                     3  yes
add_step "vm106"                "VM106 media-ai install"                                           4  yes
add_step "vm107"                "VM107 Chia farmer install"                                        4  yes
add_step "vm110"                "VM110 PBS backup install"                                         3  yes
add_step "docker_hosts"         "Prepare all Docker hosts"                                         6  yes
add_step "svc_arr"              "ARR stack service install"                                        3  yes
add_step "svc_seerr"            "Seerr service install"                                            2  yes
add_step "svc_uptime"           "Uptime Kuma service install"                                      2  yes
add_step "svc_nextcloud"        "Bacscloud/Nextcloud service install"                              3  yes
add_step "svc_jellyfin"         "Jellyfin service install"                                         3  yes
add_step "svc_immich"           "Immich service install"                                           3  yes
add_step "svc_ollama"           "Ollama/OpenWebUI service install"                                 3  yes
add_step "svc_lidarr"           "Lidarr service install"                                           2  yes
add_step "svc_homeassistant"    "Home Assistant service install"                                   2  yes
add_step "svc_pbs"              "PBS service install/config inside VM110"                          2  yes
add_step "repair_basics"        "Basic repair/config polish"                                       4  no
add_step "core_config"          "Run all core service config scripts"                              4  no
add_step "phase4"               "SMTP / Uptime Kuma / PBS automation / Chia"                       5  yes
add_step "cloudflared_final"    "Final Cloudflared remote access setup"                            3  yes
add_step "final_health"         "Final VM/resource/service health checks"                          3  no

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "❌ Root olarak çalıştırmalısın."
    exit 1
  fi
}

has_whiptail() { command -v whiptail >/dev/null 2>&1; }
has_dialog() { command -v dialog >/dev/null 2>&1; }

ui_msg() {
  local title="$1" text="$2" height="${3:-18}" width="${4:-78}"
  if has_whiptail; then
    whiptail --title "$title" --msgbox "$text" "$height" "$width" || true
  elif has_dialog; then
    dialog --title "$title" --msgbox "$text" "$height" "$width" || true
    clear || true
  else
    echo
    echo "===== $title ====="
    echo "$text"
    echo
    read -r -p "Devam için Enter..." _ || true
  fi
}

ui_yesno() {
  local title="$1" text="$2" height="${3:-16}" width="${4:-78}"
  if has_whiptail; then
    whiptail --title "$title" --yesno "$text" "$height" "$width"
  elif has_dialog; then
    dialog --title "$title" --yesno "$text" "$height" "$width"
    local rc=$?
    clear || true
    return "$rc"
  else
    local ans
    echo
    echo "===== $title ====="
    echo "$text"
    read -r -p "[y/N]: " ans || true
    [[ "$ans" =~ ^[Yy]$ ]]
  fi
}

ui_menu() {
  local title="$1" text="$2" height="$3" width="$4" menu_height="$5"
  shift 5
  local choice
  if has_whiptail; then
    choice=$(whiptail --title "$title" --menu "$text" "$height" "$width" "$menu_height" "$@" 3>&1 1>&2 2>&3) || return 1
    printf '%s' "$choice"
  elif has_dialog; then
    choice=$(dialog --title "$title" --menu "$text" "$height" "$width" "$menu_height" "$@" 3>&1 1>&2 2>&3) || { clear || true; return 1; }
    clear || true
    printf '%s' "$choice"
  else
    local items=("$@") i ans
    echo
    echo "===== $title ====="
    echo "$text"
    i=0
    while (( i < ${#items[@]} )); do
      printf '  %s) %s\n' "${items[$i]}" "${items[$((i+1))]}"
      i=$((i+2))
    done
    read -r -p "Seçim: " ans || return 1
    printf '%s' "$ans"
  fi
}

pause_plain() {
  read -r -p "Devam için Enter..." _ || true
}

ensure_session() {
  if [[ -f "$SESSION_FILE" ]]; then
    SESSION_DIR="$(cat "$SESSION_FILE" 2>/dev/null || true)"
  fi
  if [[ -z "$SESSION_DIR" || ! -d "$SESSION_DIR" ]]; then
    SESSION_DIR="$LOG_ROOT/v3-session-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$SESSION_DIR"
    echo "$SESSION_DIR" > "$SESSION_FILE"
    chmod 600 "$SESSION_FILE" 2>/dev/null || true
  fi
  MASTER_LOG="$SESSION_DIR/00-v3-master.log"
  touch "$MASTER_LOG" "$STATE_FILE"
  chmod 600 "$MASTER_LOG" "$STATE_FILE" 2>/dev/null || true
}

new_session() {
  SESSION_DIR="$LOG_ROOT/v3-session-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$SESSION_DIR"
  echo "$SESSION_DIR" > "$SESSION_FILE"
  MASTER_LOG="$SESSION_DIR/00-v3-master.log"
  : > "$MASTER_LOG"
  : > "$STATE_FILE"
  chmod 600 "$MASTER_LOG" "$STATE_FILE" 2>/dev/null || true
}

log_master() {
  ensure_session
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$MASTER_LOG"
}

state_status() {
  local id="$1"
  [[ -f "$STATE_FILE" ]] || return 0
  awk -F'|' -v id="$id" '$1==id {s=$2} END{print s}' "$STATE_FILE"
}

state_mark() {
  local id="$1" status="$2" title="$3" tmp
  ensure_session
  tmp="$(mktemp)"
  awk -F'|' -v id="$id" '$1!=id {print}' "$STATE_FILE" > "$tmp" || true
  printf '%s|%s|%s|%s\n' "$id" "$status" "$(date '+%F %T')" "$title" >> "$tmp"
  cat "$tmp" > "$STATE_FILE"
  rm -f "$tmp"
  log_master "STATE $id -> $status :: $title"
}

state_is_complete() {
  local s
  s="$(state_status "$1")"
  [[ "$s" == "done" || "$s" == "skipped" || "$s" == "warn" ]]
}

total_weight() {
  local total=0 w
  for w in "${STEP_WEIGHTS[@]}"; do total=$((total + w)); done
  echo "$total"
}

completed_weight() {
  local total=0 i id status
  for i in "${!STEP_IDS[@]}"; do
    id="${STEP_IDS[$i]}"
    status="$(state_status "$id")"
    case "$status" in
      done|skipped|warn) total=$((total + STEP_WEIGHTS[$i])) ;;
    esac
  done
  echo "$total"
}

progress_percent() {
  local done total
  done="$(completed_weight)"
  total="$(total_weight)"
  if [[ "$total" -le 0 ]]; then echo 0; else echo $((done * 100 / total)); fi
}

progress_bar() {
  local percent="$1" width="${2:-32}" filled empty
  filled=$((percent * width / 100))
  empty=$((width - filled))
  printf '%*s' "$filled" '' | tr ' ' '#'
  printf '%*s' "$empty" '' | tr ' ' '-'
}

progress_text() {
  local percent bar i id title status icon lines=""
  percent="$(progress_percent)"
  bar="$(progress_bar "$percent" 34)"
  lines+="Genel ilerleme: ${percent}%\n[$bar]\n\n"
  lines+="Log session:\n$SESSION_DIR\n\n"
  for i in "${!STEP_IDS[@]}"; do
    id="${STEP_IDS[$i]}"
    title="${STEP_TITLES[$i]}"
    status="$(state_status "$id")"
    case "$status" in
      done) icon="✅" ;;
      skipped) icon="↷" ;;
      warn) icon="⚠️" ;;
      failed) icon="❌" ;;
      running) icon="⏳" ;;
      *) icon="⬜" ;;
    esac
    lines+="$icon $title\n"
  done
  printf '%b' "$lines"
}

show_progress() {
  ensure_session
  ui_msg "Homelab v3.0 ilerleme" "$(progress_text)" 36 100
}

view_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    ui_msg "Log bulunamadı" "$file bulunamadı."
    return 0
  fi
  clear || true
  if command -v less >/dev/null 2>&1; then
    less -R "$file" || true
  else
    tail -n 240 "$file" || true
    pause_plain
  fi
}

show_log_menu() {
  ensure_session
  local files=() items=() f base choice idx=1
  while IFS= read -r f; do
    files+=("$f")
    base="$(basename "$f")"
    items+=("$idx" "$base")
    idx=$((idx+1))
  done < <(find "$SESSION_DIR" -maxdepth 1 -type f -name '*.log' | sort)
  if [[ ${#files[@]} -eq 0 ]]; then
    ui_msg "Loglar" "Bu session içinde log dosyası yok.\n\n$SESSION_DIR"
    return 0
  fi
  choice="$(ui_menu "Homelab v3.0 logları" "Açmak istediğin log dosyasını seç:" 24 92 14 "${items[@]}" "B" "Geri")" || return 0
  [[ "$choice" == "B" ]] && return 0
  if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#files[@]} ]]; then
    view_file "${files[$((choice-1))]}"
  fi
}

run_logged_command() {
  local label="$1"
  shift
  ensure_session
  echo | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG" >/dev/null
  echo "==================================================" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
  echo "[$(date '+%F %T')] $label" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
  echo "Command: $*" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
  echo "==================================================" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"

  set +e
  "$@" 2>&1 | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
  local rc=${PIPESTATUS[0]}
  set -e

  echo "[$(date '+%F %T')] Exit code: $rc" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
  return "$rc"
}

run_optional_logged_command() {
  local label="$1"
  shift
  run_logged_command "$label" "$@" || {
    local rc=$?
    echo "⚠️ Opsiyonel/devam edilebilir komut hata verdi ($rc): $label" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    return 0
  }
}

run_script_path() {
  local script="$1"
  shift || true
  if [[ ! -f "$ROOT_DIR/$script" ]]; then
    echo "❌ Script bulunamadı: $script" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    return 127
  fi
  run_logged_command "$script" "$@" bash "$ROOT_DIR/$script"
}

run_optional_script_path() {
  local script="$1"
  shift || true
  if [[ ! -f "$ROOT_DIR/$script" ]]; then
    echo "⚠️ Opsiyonel script bulunamadı: $script" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    return 0
  fi
  run_optional_logged_command "$script" "$@" bash "$ROOT_DIR/$script"
}

# --- TrueNAS guided checkpoint helpers copied into v3 wrapper, not modifying legacy menu. ---
quarantine_truenas_api_envs() {
  local reason="${1:-fresh TrueNAS API regeneration required}"
  local secrets="${SECRETS_DIR:-/root/homelab-secrets}"
  local stamp qdir f
  stamp="$(date +%Y%m%d-%H%M%S)"
  qdir="$secrets/quarantine/truenas-api-${stamp}"
  mkdir -p "$qdir"
  chmod 700 "$secrets" "$secrets/quarantine" "$qdir" 2>/dev/null || true

  shopt -s nullglob
  for f in \
    "$secrets/truenas-api.env" \
    "$secrets/truenas.env" \
    "$secrets"/*truenas-api* \
    "$secrets"/*TRUENAS_API*; do
    [[ -e "$f" ]] || continue
    [[ "$f" == "$secrets/quarantine"* ]] && continue
    echo "⚠️ Eski/import edilmiş TrueNAS API dosyası kullanılmayacak: $(basename "$f")" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    mv -f "$f" "$qdir/" 2>/dev/null || rm -f "$f" || true
  done
  shopt -u nullglob

  if [[ -z "$(find "$qdir" -type f -print -quit 2>/dev/null)" ]]; then
    rmdir "$qdir" 2>/dev/null || true
  else
    echo "ℹ️ TrueNAS API dosyaları quarantine edildi: $qdir" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    echo "   Sebep: $reason" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
  fi
}

mark_fresh_truenas_api_required() {
  local marker="${SECRETS_DIR:-/root/homelab-secrets}/.fresh-truenas-api-required"
  mkdir -p "${SECRETS_DIR:-/root/homelab-secrets}"
  touch "$marker"
  chmod 600 "$marker" 2>/dev/null || true
}

clear_fresh_truenas_api_marker() {
  rm -f "${SECRETS_DIR:-/root/homelab-secrets}/.fresh-truenas-api-required" 2>/dev/null || true
}

truenas_vm_mac() {
  qm config 101 2>/dev/null | sed -nE 's/^net[0-9]+:.*=(([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}).*/\1/p' | head -n1 | tr '[:upper:]' '[:lower:]'
}

truenas_vm_bridge() {
  qm config 101 2>/dev/null | sed -nE 's/^net[0-9]+:.*bridge=([^, ]+).*/\1/p' | head -n1
}

switch_truenas_to_disk_boot() {
  echo | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG" >/dev/null
  echo "💿 TrueNAS VM101 installer ISO/CD kaldırılıyor ve disk boot'a alınıyor..." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
  qm stop 101 || true
  sleep 3
  qm set 101 --ide2 none || true
  qm set 101 --boot order=scsi0
  qm start 101
  echo "✅ VM101 diskten boot edecek şekilde başlatıldı." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
  echo "⏳ TrueNAS boot için 60 saniye bekleniyor..." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
  sleep 60
}

start_truenas_installer_if_needed() {
  if ! qm status 101 >/dev/null 2>&1; then
    echo "❌ VM101 bulunamadı. Önce vm/101-truenas-vm-install.sh çalışmalı." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    return 1
  fi
  if qm status 101 2>/dev/null | grep -q 'status: running'; then
    echo "✅ VM101 zaten çalışıyor." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
  else
    echo "▶️ VM101 TrueNAS installer başlatılıyor..." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    qm start 101 || true
    sleep 5
  fi
  echo "ℹ️ Proxmox UI > VM101 > Console ekranından TrueNAS installer'ı tamamla." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
}

find_truenas_ip_by_mac() {
  local mac bridge subnet ip
  mac="$(truenas_vm_mac)"
  bridge="$(truenas_vm_bridge)"
  bridge="${bridge:-vmbr0}"
  subnet="192.168.50.0/24"
  [[ -n "$mac" ]] || return 1
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y nmap arp-scan >/dev/null 2>&1 || true
  ip neigh flush all >/dev/null 2>&1 || true
  nmap -sn "$subnet" >/dev/null 2>&1 || true
  ip="$(ip neigh show | awk -v mac="$mac" '$1 ~ /^192\.168\.50\./ && tolower($5)==mac {print $1; exit}')"
  if [[ -z "$ip" ]]; then
    ip="$(arp-scan -I "$bridge" "$subnet" 2>/dev/null | awk -v mac="$mac" '$1 ~ /^192\.168\.50\./ && tolower($2)==mac {print $1; exit}')"
  fi
  [[ -n "$ip" ]] && echo "$ip"
}

refresh_truenas_known_host() {
  local ip="${1:-192.168.50.101}"
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  touch /root/.ssh/known_hosts
  chmod 600 /root/.ssh/known_hosts
  ssh-keygen -f /root/.ssh/known_hosts -R "$ip" >/dev/null 2>&1 || true
  ssh-keygen -f /root/.ssh/known_hosts -R "[$ip]:22" >/dev/null 2>&1 || true
  ssh-keyscan -H "$ip" >> /root/.ssh/known_hosts 2>/dev/null || true
}

test_truenas_ssh_from_login_env() {
  local ip="$1" login_env user pass
  login_env="${SECRETS_DIR:-/root/homelab-secrets}/truenas-login.env"
  [[ -f "$login_env" ]] || return 1
  # shellcheck disable=SC1090
  source "$login_env"
  user="${TRUENAS_SSH_USER:-truenas_admin}"
  pass="${TRUENAS_SSH_PASS:-}"
  [[ -n "$pass" ]] || return 1
  apt-get install -y sshpass openssh-client >/dev/null 2>&1 || true
  refresh_truenas_known_host "$ip"
  sshpass -p "$pass" ssh \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile=/root/.ssh/known_hosts \
    -o ConnectTimeout=8 \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    "$user@$ip" 'echo SSH_OK' 2>/tmp/truenas-ssh-test.err | grep -q SSH_OK
}

truenas_checkpoint_already_done() {
  local ip="${1:-192.168.50.101}"
  if qm config 101 2>/dev/null | grep -Eq '^ide2: .*iso'; then
    return 1
  fi
  if (curl -fsS --max-time 5 "http://$ip" >/dev/null 2>&1 || ping -c1 -W1 "$ip" >/dev/null 2>&1) && test_truenas_ssh_from_login_env "$ip"; then
    echo "✅ TrueNAS disk boot + WebUI/SSH checkpoint zaten tamam görünüyor: $ip" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    return 0
  fi
  return 1
}

wait_for_truenas_manual_install_and_ssh() {
  local ip web_choice login_env user pass found
  login_env="${SECRETS_DIR:-/root/homelab-secrets}/truenas-login.env"
  ip="192.168.50.101"

  if truenas_checkpoint_already_done "$ip"; then
    return 0
  fi

  start_truenas_installer_if_needed || return 1

  while true; do
    if ui_yesno "MANUEL DURAK: TrueNAS kurulumu" "VM101 Console'da TrueNAS installer'ı manuel bitir.\n\nÖnemli:\n- Kurulumda SADECE 64GB OS diskini seç.\n- Kurulum bittiğinde Yes de; v3 TUI ISO'yu kaldırıp VM101'i disk boot'a alacak.\n\nTrueNAS kurulumu bitti mi?" 18 88; then
      break
    fi
    ui_msg "TrueNAS bekleniyor" "TrueNAS kurulumu bitince tekrar Yes seç.\n\nBu ekran bekleme amaçlıdır; kurulum iptal edilmedi." 12 70
  done

  if qm config 101 2>/dev/null | grep -Eq '^ide2: .*iso'; then
    switch_truenas_to_disk_boot
  else
    echo "ℹ️ VM101 üzerinde installer ISO görünmüyor; boot-fix adımı atlandı." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    qm start 101 >/dev/null 2>&1 || true
  fi

  while true; do
    if curl -fsS --max-time 5 "http://$ip" >/dev/null 2>&1 || ping -c1 -W1 "$ip" >/dev/null 2>&1; then
      echo "✅ $ip erişilebilir görünüyor." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    else
      echo "⚠️ $ip henüz erişilebilir görünmüyor." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    fi

    web_choice="$(ui_menu "TrueNAS WebUI kontrolü" "TrueNAS WebUI erişimini doğrula.\n\nÖncelikli adres: http://$ip" 18 88 6 \
      "Y" "WebUI bu adreste erişilebilir" \
      "S" "DHCP/MAC ağı tara" \
      "W" "10 saniye bekle ve tekrar dene" \
      "Q" "Kurulumu durdur")" || true
    case "$web_choice" in
      Y) break ;;
      S)
        echo "🔎 DHCP/MAC ağ taraması başlıyor..." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
        found="$(find_truenas_ip_by_mac || true)"
        if [[ -n "$found" ]]; then
          ip="$found"
          echo "✅ TrueNAS aday IP bulundu: http://$ip" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
        else
          ui_msg "IP bulunamadı" "TrueNAS IP bulunamadı. 10 saniye sonra tekrar deneyebilirsin." 12 70
        fi
        ;;
      W|"") sleep 10 ;;
      Q) return 1 ;;
      *) sleep 5 ;;
    esac
  done

  ui_msg "SSH açma adımı" "TrueNAS WebUI > System Settings > Services > SSH > Edit:\n\n- Allow Password Authentication: ON\n- Password Login Groups: builtin_administrators veya truenas_admin'in admin grubu\n- Save\n- SSH Start\n- İstersen Start Automatically açık kalsın\n\nSonraki ekranda SSH test edilecek." 18 88

  [[ -f "$login_env" ]] || { echo "❌ $login_env yok. Önce Secrets/env bootstrap çalışmalı." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"; return 1; }
  # shellcheck disable=SC1090
  source "$login_env"
  user="${TRUENAS_SSH_USER:-truenas_admin}"
  pass="${TRUENAS_SSH_PASS:-}"
  [[ -n "$pass" ]] || { echo "❌ TRUENAS_SSH_PASS boş." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"; return 1; }

  while true; do
    if ui_yesno "TrueNAS SSH kontrolü" "SSH servisini açtıysan Yes seç.\n\nTest edilecek adres:\n$user@$ip" 14 76; then
      if test_truenas_ssh_from_login_env "$ip"; then
        echo "✅ TrueNAS SSH bağlantısı başarılı: $user@$ip" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
        if grep -q '^TRUENAS_HOST=' "$login_env"; then
          sed -i "s/^TRUENAS_HOST=.*/TRUENAS_HOST=$ip/" "$login_env" || true
        else
          echo "TRUENAS_HOST=$ip" >> "$login_env"
        fi
        mark_fresh_truenas_api_required
        return 0
      fi
      echo "❌ SSH bağlanılamadı." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
      cat /tmp/truenas-ssh-test.err 2>/dev/null | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG" || true
      ui_msg "SSH başarısız" "SSH bağlantısı başarısız.\n\nHatırlatma:\n- SSH Running olmalı\n- Allow Password Authentication açık olmalı\n- Password Login Groups içine builtin_administrators veya truenas_admin'in admin grubu eklenmeli" 16 82
    else
      ui_msg "SSH bekleniyor" "SSH açıldığında tekrar Yes seç. Kurulum iptal edilmedi." 10 70
    fi
  done
}

ensure_truenas_api_ready_v3() {
  local api_env="${SECRETS_DIR:-/root/homelab-secrets}/truenas-api.env"
  local login_env="${SECRETS_DIR:-/root/homelab-secrets}/truenas-login.env"
  local marker="${SECRETS_DIR:-/root/homelab-secrets}/.fresh-truenas-api-required"

  if [[ -f "$marker" || "${HOMELAB_FORCE_NEW_TRUENAS_API:-1}" == "1" ]]; then
    echo "🔑 Fresh TrueNAS API key zorunlu; mevcut/import edilmiş API env kullanılmayacak." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    quarantine_truenas_api_envs "fresh TrueNAS API regeneration"
  elif [[ -f "$api_env" ]]; then
    echo "✅ TrueNAS API env mevcut: $api_env" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    return 0
  fi

  if [[ ! -f "$login_env" ]]; then
    echo "❌ $login_env yok. Önce Secrets/env bootstrap çalıştır." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    return 1
  fi

  echo "✅ truenas-login.env mevcut. Post-install helper otomatik çalışacak ve yeni API key üretecek." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
  run_logged_command "TrueNAS postinstall import/API/network" env TRUENAS_SSH_READY_ASSUMED=1 TRUENAS_SKIP_BOOT_FIX=1 bash "$ROOT_DIR/services/truenas/00-truenas-postinstall-import-api-network.sh" || return $?
  [[ -f "$api_env" ]] || { echo "❌ Helper bitti ama $api_env oluşmadı." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"; return 1; }
  clear_fresh_truenas_api_marker
  echo "✅ Fresh TrueNAS API env üretildi: $api_env" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
}

# --- Step implementations. ---
step_secrets() { run_script_path "bootstrap/00-bootstrap-secrets.sh"; }

step_cloudflare_prepare() {
  if ui_yesno "Early Cloudflare credential" "Cloudflare Tunnel credentials şimdi hazırlansın mı?\n\nBu adım Proxmox üzerinde browser auth linkini erken gösterir. Hazır JSON credential daha sonra VM103 final aşamasında kullanılır.\n\nAtlamak istersen final aşamada manuel/legacy akıştan devam edebilirsin." 18 88; then
    run_script_path "services/cloudflared/00-prepare-tunnel-credentials-on-proxmox.sh"
  else
    echo "↷ Early Cloudflared credential prepare kullanıcı tarafından atlandı." | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG"
    return 0
  fi
}

step_hardware_preflight() { run_optional_script_path "maintenance/health/hardware-preflight.sh"; }
step_proxmox_users() { run_script_path "bootstrap/01-create-proxmox-users.sh"; }
step_storage_normalize() { run_logged_command "bootstrap/02-normalize-local-storage.sh" env HOMELAB_DESTRUCTIVE_STORAGE_RESET=1 bash "$ROOT_DIR/bootstrap/02-normalize-local-storage.sh"; }
step_truenas_checkpoint() { run_script_path "vm/101-truenas-vm-install.sh" && wait_for_truenas_manual_install_and_ssh; }
step_truenas_storage() { ensure_truenas_api_ready_v3 && run_script_path "services/truenas/01-truenas-api-bootstrap-storage.sh"; }
step_vm102() { run_script_path "vm/102-docker-arr-vm-install.sh"; }
step_vm103() { run_script_path "vm/103-network-vm-install.sh"; }
step_vm104() { run_script_path "vm/104-nextcloud-vm-install.sh"; }
step_vm105() { run_script_path "vm/105-homeassistant-vm-install.sh"; }
step_vm106() { run_script_path "vm/106-media-ai-vm-install.sh"; }
step_vm107() { run_script_path "vm/107-chia-farmer-vm-install.sh"; }
step_vm110() { run_script_path "vm/110-pbs-backup-vm-install.sh"; }
step_docker_hosts() { run_script_path "services/common/01-prepare-all-docker-hosts.sh"; }
step_svc_arr() { run_script_path "services/arr/01-arr-service-install.sh"; }
step_svc_seerr() { run_script_path "services/seerr/01-seerr-service-install.sh"; }
step_svc_uptime() { run_script_path "services/uptime-kuma/01-uptime-kuma-service-install.sh"; }
step_svc_nextcloud() { run_script_path "services/nextcloud/01-nextcloud-service-install.sh"; }
step_svc_jellyfin() { run_script_path "services/jellyfin/01-jellyfin-service-install.sh"; }
step_svc_immich() { run_script_path "services/immich/01-immich-service-install.sh"; }
step_svc_ollama() { run_script_path "services/ollama/01-ollama-openwebui-service-install.sh"; }
step_svc_lidarr() { run_script_path "services/lidarr/01-lidarr-service-install.sh"; }
step_svc_homeassistant() { run_script_path "services/homeassistant/01-homeassistant-service-install.sh"; }
step_svc_pbs() { run_script_path "services/pbs/01-pbs-service-install.sh"; }

step_repair_basics() {
  run_optional_script_path "config/nextcloud/01-nextcloud-local-and-cloudflare-fix.sh"
  run_optional_script_path "config/nextcloud/04-bacscloud-production-hardening.sh"
  run_optional_script_path "config/nextcloud/06-bacscloud-admin-overview-cleanup.sh"
  run_optional_script_path "config/nextcloud/07-bacscloud-social-login-and-registration.sh"
  run_optional_script_path "config/immich/01-immich-storage-verify.sh"
  run_optional_script_path "services/cloudflared/02-generate-ingress-config-reference.sh"
  return 0
}

step_core_config() {
  run_optional_script_path "config/00-run-all-core-config.sh"
  return 0
}

step_phase4() {
  run_optional_script_path "config/smtp/01-write-service-smtp-reference.sh"
  run_optional_script_path "config/uptime-kuma/02-uptime-kuma-auto-config.sh"
  run_optional_script_path "config/pbs/01-pbs-backup-automation.sh"
  run_script_path "services/chia/01-chia-farmer-service-install.sh"
}

step_cloudflared_final() { run_script_path "services/cloudflared/01-cloudflared-service-install.sh"; }

step_final_health() {
  run_optional_script_path "maintenance/health/vm-resource-audit.sh"
  run_optional_script_path "maintenance/health/full-health-check.sh"
  run_optional_script_path "maintenance/health/full-service-audit.sh"
  return 0
}

run_step_function() {
  local id="$1"
  case "$id" in
    secrets) step_secrets ;;
    cloudflare_prepare) step_cloudflare_prepare ;;
    hardware_preflight) step_hardware_preflight ;;
    proxmox_users) step_proxmox_users ;;
    storage_normalize) step_storage_normalize ;;
    truenas_checkpoint) step_truenas_checkpoint ;;
    truenas_storage) step_truenas_storage ;;
    vm102) step_vm102 ;;
    vm103) step_vm103 ;;
    vm104) step_vm104 ;;
    vm105) step_vm105 ;;
    vm106) step_vm106 ;;
    vm107) step_vm107 ;;
    vm110) step_vm110 ;;
    docker_hosts) step_docker_hosts ;;
    svc_arr) step_svc_arr ;;
    svc_seerr) step_svc_seerr ;;
    svc_uptime) step_svc_uptime ;;
    svc_nextcloud) step_svc_nextcloud ;;
    svc_jellyfin) step_svc_jellyfin ;;
    svc_immich) step_svc_immich ;;
    svc_ollama) step_svc_ollama ;;
    svc_lidarr) step_svc_lidarr ;;
    svc_homeassistant) step_svc_homeassistant ;;
    svc_pbs) step_svc_pbs ;;
    repair_basics) step_repair_basics ;;
    core_config) step_core_config ;;
    phase4) step_phase4 ;;
    cloudflared_final) step_cloudflared_final ;;
    final_health) step_final_health ;;
    *) echo "Bilinmeyen step: $id"; return 127 ;;
  esac
}

handle_step_failure() {
  local id="$1" title="$2" critical="$3" rc="$4" choice
  while true; do
    if [[ "$critical" == "yes" ]]; then
      choice="$(ui_menu "Kritik adım başarısız" "Adım hata verdi: $title\nExit code: $rc\n\nLog:\n$CURRENT_STEP_LOG\n\nNe yapmak istersin?" 20 90 8 \
        "R" "Tekrar dene" \
        "L" "Logu göster" \
        "M" "Legacy install-menu.sh aç" \
        "S" "Kurulumu durdur")" || choice="S"
      case "$choice" in
        R) return 10 ;;
        L) view_file "$CURRENT_STEP_LOG" ;;
        M) bash "$ROOT_DIR/menu/install-menu.sh" ;;
        S|*) return 1 ;;
      esac
    else
      choice="$(ui_menu "Opsiyonel adım hata verdi" "Opsiyonel/devam edilebilir adım hata verdi: $title\nExit code: $rc\n\nLog:\n$CURRENT_STEP_LOG" 20 90 8 \
        "C" "Devam et / uyarı olarak işaretle" \
        "R" "Tekrar dene" \
        "L" "Logu göster" \
        "S" "Kurulumu durdur")" || choice="C"
      case "$choice" in
        C) state_mark "$id" "warn" "$title"; return 0 ;;
        R) return 10 ;;
        L) view_file "$CURRENT_STEP_LOG" ;;
        S) return 1 ;;
        *) state_mark "$id" "warn" "$title"; return 0 ;;
      esac
    fi
  done
}

run_one_step_by_index() {
  local i="$1" force="${2:-0}" id title critical percent bar rc action
  id="${STEP_IDS[$i]}"
  title="${STEP_TITLES[$i]}"
  critical="${STEP_CRITICAL[$i]}"

  if [[ "$force" != "1" ]] && state_is_complete "$id"; then
    echo "✅ Zaten tamamlanmış, atlanıyor: $title" | tee -a "$MASTER_LOG"
    return 0
  fi

  CURRENT_STEP_ID="$id"
  CURRENT_STEP_TITLE="$title"
  CURRENT_STEP_INDEX="$((i+1))"
  CURRENT_STEP_LOG="$SESSION_DIR/$(printf '%02d' "$CURRENT_STEP_INDEX")-${id}.log"
  touch "$CURRENT_STEP_LOG"
  chmod 600 "$CURRENT_STEP_LOG" 2>/dev/null || true

  percent="$(progress_percent)"
  bar="$(progress_bar "$percent" 34)"
  ui_msg "Homelab v3.0 - Adım $CURRENT_STEP_INDEX/${#STEP_IDS[@]}" "Genel ilerleme: ${percent}%\n[$bar]\n\nŞimdi çalışacak adım:\n$title\n\nLog:\n$CURRENT_STEP_LOG\n\nNot: v3.0 güvenli modda mevcut backend scriptleri aynen çalıştırır. Script interaktif soru sorarsa terminalde cevaplamaya devam edebilirsin." 22 92

  while true; do
    state_mark "$id" "running" "$title"
    set +e
    run_step_function "$id"
    rc=$?
    set -e

    if [[ "$rc" -eq 0 ]]; then
      state_mark "$id" "done" "$title"
      return 0
    fi

    state_mark "$id" "failed" "$title"
    set +e
    handle_step_failure "$id" "$title" "$critical" "$rc"
    action=$?
    set -e
    case "$action" in
      0) return 0 ;;
      10) echo "🔁 Tekrar deneniyor: $title" | tee -a "$CURRENT_STEP_LOG" "$MASTER_LOG" ;;
      *) return 1 ;;
    esac
  done
}

run_guided_install() {
  ensure_session
  ui_msg "Homelab v3.0 Guided Install" "Bu v3.0 TUI, mevcut çalışan v2.4.7 backend scriptlerine dokunmadan onları sırayla çağırır.\n\nÖzellikler:\n- Phase/script bazlı yüzde ilerleme\n- Kaldığı yerden devam state'i\n- Her adım için ayrı log\n- Hata ekranında retry/log/legacy menü\n\nMevcut tamamlanan adımlar otomatik atlanır." 20 92

  local i
  for i in "${!STEP_IDS[@]}"; do
    show_progress
    run_one_step_by_index "$i" 0 || return $?
  done
  show_progress
  ui_msg "Homelab v3.0 tamamlandı" "✅ Guided install tamamlandı.\n\nSession logları:\n$SESSION_DIR\n\nMaster log:\n$MASTER_LOG" 14 82
}

run_single_step() {
  ensure_session
  local items=() i choice
  for i in "${!STEP_IDS[@]}"; do
    items+=("$((i+1))" "${STEP_TITLES[$i]} [$(state_status "${STEP_IDS[$i]}" | sed 's/^$/pending/')]")
  done
  items+=("B" "Geri")
  choice="$(ui_menu "Tek adım çalıştır" "Çalıştırmak istediğin adımı seç:" 34 106 24 "${items[@]}")" || return 0
  [[ "$choice" == "B" ]] && return 0
  if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#STEP_IDS[@]} ]]; then
    if ui_yesno "Adımı çalıştır" "Seçilen adım:\n${STEP_TITLES[$((choice-1))]}\n\nDaha önce tamamlandıysa bile tekrar çalıştırılsın mı?" 14 82; then
      run_one_step_by_index "$((choice-1))" 1 || true
    else
      run_one_step_by_index "$((choice-1))" 0 || true
    fi
  fi
}

show_state_plain() {
  ensure_session
  clear || true
  echo "Homelab v3.0 state"
  echo "State file : $STATE_FILE"
  echo "Session    : $SESSION_DIR"
  echo
  column -t -s '|' "$STATE_FILE" 2>/dev/null || cat "$STATE_FILE"
  echo
  pause_plain
}

reset_state_confirmed() {
  if ui_yesno "State sıfırlama" "Sadece v3 TUI state dosyası sıfırlanacak.\n\nMevcut VM'ler, servisler veya homelab scriptleri silinmez.\nYeni bir log session açılır.\n\nDevam edilsin mi?" 16 82; then
    new_session
    ui_msg "State sıfırlandı" "Yeni session:\n$SESSION_DIR"
  fi
}

legacy_menu() {
  clear || true
  echo "Legacy Homelab install-menu.sh açılıyor..."
  echo "Çıkınca v3 TUI'ye dönebilirsin."
  sleep 1
  bash "$ROOT_DIR/menu/install-menu.sh" || true
}

main_menu() {
  local choice
  while true; do
    ensure_session
    choice="$(ui_menu "Homelab v3.0 Terminal Installer" "$(printf 'Genel ilerleme: %s%%\nSession: %s\n\nNe yapmak istersin?' "$(progress_percent)" "$SESSION_DIR")" 24 94 12 \
      "1" "Guided full install / Resume" \
      "2" "İlerlemeyi göster" \
      "3" "Tek adım çalıştır" \
      "4" "Session loglarını göster" \
      "5" "State dosyasını göster" \
      "6" "Legacy install-menu.sh aç" \
      "7" "v3 state'i sıfırla / yeni session" \
      "0" "Çıkış")" || choice="0"
    case "$choice" in
      1) run_guided_install || ui_msg "Guided install durdu" "Guided install tamamlanmadı veya kullanıcı tarafından durduruldu.\n\nLoglar:\n$SESSION_DIR" 14 82 ;;
      2) show_progress ;;
      3) run_single_step ;;
      4) show_log_menu ;;
      5) show_state_plain ;;
      6) legacy_menu ;;
      7) reset_state_confirmed ;;
      0) clear || true; echo "Homelab v3.0 TUI kapatıldı. Loglar: $SESSION_DIR"; exit 0 ;;
      *) ui_msg "Geçersiz seçim" "Lütfen menüden geçerli bir seçim yap." ;;
    esac
  done
}

need_root
ensure_session
log_master "Homelab v3.0 TUI started. ROOT_DIR=$ROOT_DIR SESSION_DIR=$SESSION_DIR"
main_menu
