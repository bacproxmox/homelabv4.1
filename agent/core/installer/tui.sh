#!/usr/bin/env bash
set -Eeuo pipefail

export TERM="${TERM:-xterm}"
export HOMELAB_VERSION="${HOMELAB_VERSION:-3.1.1-r2}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$HOMELAB_ROOT/lib/core/env.sh"
source "$HOMELAB_ROOT/lib/core/logging.sh"
source "$HOMELAB_ROOT/lib/core/state.sh"
source "$HOMELAB_ROOT/lib/core/runner.sh"
source "$HOMELAB_ROOT/lib/core/ui.sh"

MANIFEST="${MANIFEST:-$HOMELAB_ROOT/manifests/guided-steps.tsv}"
SESSION_FILE="$STATE_DIR/current-session"
SESSION_DIR=""
MASTER_LOG=""

declare -a STEP_IDS=()
declare -a STEP_TITLES=()
declare -a STEP_WEIGHTS=()
declare -a STEP_CRITICAL=()
declare -a STEP_TARGETS=()

load_manifest() {
  STEP_IDS=()
  STEP_TITLES=()
  STEP_WEIGHTS=()
  STEP_CRITICAL=()
  STEP_TARGETS=()
  local id title weight critical target
  while IFS='|' read -r id title weight critical target; do
    [[ -n "${id:-}" ]] || continue
    [[ "$id" == \#* ]] && continue
    STEP_IDS+=("$id")
    STEP_TITLES+=("$title")
    STEP_WEIGHTS+=("$weight")
    STEP_CRITICAL+=("$critical")
    STEP_TARGETS+=("$target")
  done < "$MANIFEST"
}

ensure_session() {
  if [[ -f "$SESSION_FILE" ]]; then
    SESSION_DIR="$(cat "$SESSION_FILE" 2>/dev/null || true)"
  fi
  if [[ -z "$SESSION_DIR" || ! -d "$SESSION_DIR" ]]; then
    SESSION_DIR="$LOG_DIR/v3.1.1-r2-session-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$SESSION_DIR"
    echo "$SESSION_DIR" > "$SESSION_FILE"
    chmod 600 "$SESSION_FILE" 2>/dev/null || true
  fi
  MASTER_LOG="$SESSION_DIR/00-v3.1.1-r2-master.log"
  touch "$MASTER_LOG"
  chmod 600 "$MASTER_LOG" 2>/dev/null || true
}

new_session() {
  SESSION_DIR="$LOG_DIR/v3.1.1-r2-session-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$SESSION_DIR"
  echo "$SESSION_DIR" > "$SESSION_FILE"
  MASTER_LOG="$SESSION_DIR/00-v3.1.1-r2-master.log"
  : > "$MASTER_LOG"
  : > "$STATE_FILE"
  chmod 600 "$SESSION_FILE" "$MASTER_LOG" "$STATE_FILE" 2>/dev/null || true
}

log_master() {
  ensure_session
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$MASTER_LOG"
}

total_weight() {
  local total=0 weight
  for weight in "${STEP_WEIGHTS[@]}"; do
    total=$((total + weight))
  done
  echo "$total"
}

completed_weight() {
  local total=0 i status
  for i in "${!STEP_IDS[@]}"; do
    status="$(state_status "${STEP_IDS[$i]}")"
    case "$status" in
      done|skipped) total=$((total + STEP_WEIGHTS[$i])) ;;
    esac
  done
  echo "$total"
}

progress_percent() {
  local done total
  done="$(completed_weight)"
  total="$(total_weight)"
  [[ "$total" -le 0 ]] && echo 0 || echo $((done * 100 / total))
}

progress_bar() {
  local percent="$1" width="${2:-34}" filled empty
  filled=$((percent * width / 100))
  empty=$((width - filled))
  printf '%*s' "$filled" '' | tr ' ' '#'
  printf '%*s' "$empty" '' | tr ' ' '-'
}

progress_text() {
  local percent bar i status icon lines=""
  percent="$(progress_percent)"
  bar="$(progress_bar "$percent")"
  lines+="Genel ilerleme: ${percent}%\n[$bar]\n\n"
  lines+="Log session:\n$SESSION_DIR\n\n"
  for i in "${!STEP_IDS[@]}"; do
    status="$(state_status "${STEP_IDS[$i]}")"
    case "$status" in
      done) icon="[OK]" ;;
      skipped) icon="[SKIP]" ;;
      warn) icon="[WARN/RETRY]" ;;
      failed) icon="[FAIL]" ;;
      running) icon="[RUN]" ;;
      *) icon="[ ]" ;;
    esac
    lines+="$icon ${STEP_TITLES[$i]}\n"
  done
  printf '%b' "$lines"
}

render_progress_dashboard() {
  local idx="${1:-0}" title="${2:-}" target="${3:-}" step_log="${4:-}" percent bar
  percent="$(progress_percent)"
  bar="$(progress_bar "$percent" 48)"
  clear || true
  echo "============================================================"
  echo " Homelab v3.1.1-r2 Modular Guided Install"
  echo "============================================================"
  echo
  printf 'Genel ilerleme: %s%%\n[%s]\n' "$percent" "$bar"
  echo
  if [[ -n "$title" ]]; then
    printf 'Calisan adim: %s/%s\n' "$idx" "${#STEP_IDS[@]}"
    printf 'Baslik     : %s\n' "$title"
    printf 'Target     : %s\n' "$target"
    printf 'Log        : %s\n' "$step_log"
    echo
  fi
  echo "Session    : $SESSION_DIR"
  echo "Master log : $MASTER_LOG"
  echo
  echo "Adim durumlari:"
  progress_text | sed '1,6d'
  echo
  echo "Not: TrueNAS manuel kurulum/checkpoint disinda guided akista adim arasi onay beklenmez. WARN adimlari resume sonrasi tekrar denenir."
  echo "------------------------------------------------------------"
}

show_progress() {
  ensure_session
  ui_msg "Homelab v3.1.1-r2 ilerleme" "$(progress_text)" 36 100
}

run_step_index() {
  local idx="$1"
  local mode="${2:-single}"
  local id="${STEP_IDS[$idx]}"
  local title="${STEP_TITLES[$idx]}"
  local critical="${STEP_CRITICAL[$idx]}"
  local target="${STEP_TARGETS[$idx]}"
  local step_log="$SESSION_DIR/$(printf '%02d' "$((idx + 1))")-${id}.log"
  local percent bar rc

  ensure_session
  if state_is_complete "$id"; then
    log_master "SKIP already complete: $id"
    return 0
  fi

  percent="$(progress_percent)"
  bar="$(progress_bar "$percent")"
  if [[ "$mode" == "guided" ]]; then
    render_progress_dashboard "$((idx + 1))" "$title" "$target" "$step_log"
  else
    ui_msg "Homelab v3.1.1-r2 - Adim $((idx + 1))/${#STEP_IDS[@]}" "Genel ilerleme: ${percent}%\n[$bar]\n\nSimdi calisacak adim:\n$title\n\nTarget:\n$target\n\nLog:\n$step_log" 22 92
  fi

  state_mark "$id" running "$title"
  log_master "RUN $id :: $target"

  set +e
  (
    echo "Step: $id"
    echo "Title: $title"
    echo "Target: $target"
    echo "Started: $(date -Is)"
    echo
    homelab_run "$target"
  ) 2>&1 | tee "$step_log"
  rc=${PIPESTATUS[0]}
  set -e

  if [[ "$rc" -eq 0 ]]; then
    state_mark "$id" done "$title"
    log_master "DONE $id"
    [[ "$mode" == "guided" ]] && render_progress_dashboard "$((idx + 1))" "$title tamamlandi" "$target" "$step_log"
    return 0
  fi

  if [[ "$critical" == "yes" ]]; then
    state_mark "$id" failed "$title"
    log_master "FAIL $id rc=$rc"
    ui_msg "Kritik adim durdu" "$title\n\nHata kodu: $rc\nLog:\n$step_log" 14 86
    return "$rc"
  fi

  state_mark "$id" warn "$title"
  log_master "WARN $id rc=$rc"
  ui_msg "Opsiyonel adim uyardi" "$title\n\nHata kodu: $rc\nKurulum devam edecek.\nLog:\n$step_log" 14 86
  return 0
}

run_guided_install() {
  ensure_session
  render_progress_dashboard 0 "Guided install basliyor" "$MANIFEST" "$MASTER_LOG"
  local i
  for i in "${!STEP_IDS[@]}"; do
    run_step_index "$i" guided || return $?
  done
  render_progress_dashboard "${#STEP_IDS[@]}" "Guided install tamamlandi" "$MANIFEST" "$MASTER_LOG"
  echo
  echo "Guided install tamamlandi."
  echo "Session loglari: $SESSION_DIR"
  echo "Master log: $MASTER_LOG"
  sleep 3
}

run_single_step_menu() {
  ensure_session
  local items=() i choice
  for i in "${!STEP_IDS[@]}"; do
    items+=("$((i + 1))" "${STEP_TITLES[$i]} [$(state_status "${STEP_IDS[$i]}" | sed 's/^$/pending/')]")
  done
  choice="$(ui_menu "Tek adim calistir" "Calistirilacak adimi sec." 34 100 25 "${items[@]}")" || return 0
  if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#STEP_IDS[@]} ]]; then
    run_step_index "$((choice - 1))" || true
  fi
}

collect_support_bundle() {
  ensure_session
  local support_log="$SESSION_DIR/support-bundle.log"
  clear || true
  echo "Support bundle toplanıyor..."
  echo "Log: $support_log"
  set +e
  bash "$HOMELAB_ROOT/backend/v3.0/maintenance/logs/collect-support-bundle.sh" 2>&1 | tee "$support_log"
  local rc=${PIPESTATUS[0]}
  set -e
  if [[ "$rc" -eq 0 ]]; then
    ui_msg "Support bundle" "Support bundle task'i tamamlandi.\n\nLog:\n$support_log" 12 82
  else
    ui_msg "Support bundle hata" "Support bundle task'i hata verdi: $rc\n\nLog:\n$support_log" 12 82
  fi
}

main_menu() {
  load_manifest
  ensure_session
  while true; do
    local choice
    choice="$(ui_menu "Homelab v3.1.1-r2 Modular TUI" "Secim yap." 20 88 10 \
      "1" "Guided full install / Resume" \
      "2" "Tek adim calistir" \
      "3" "Ilerleme goster" \
      "4" "Yeni session baslat" \
      "5" "Legacy install menu" \
      "6" "Manifest listele" \
      "7" "Support bundle topla" \
      "0" "Cikis")" || exit 0
    case "$choice" in
      1) run_guided_install || ui_msg "Guided install durdu" "Kurulum tamamlanmadi.\n\nLoglar:\n$SESSION_DIR" 14 82 ;;
      2) run_single_step_menu ;;
      3) show_progress ;;
      4) new_session; ui_msg "Yeni session" "Yeni session baslatildi:\n$SESSION_DIR" 12 78 ;;
      5) bash "$HOMELAB_ROOT/menu/install-menu.sh" || true ;;
      6) ui_msg "Guided manifest" "$(sed 's/|/  |  /g' "$MANIFEST")" 36 120 ;;
      7) collect_support_bundle ;;
      0) exit 0 ;;
    esac
  done
}

main_menu "$@"
