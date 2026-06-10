#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/opt/homelabv4"
AGENT="$ROOT/agent"
STATE="$ROOT/state"
LOGS="$ROOT/logs"
CORE="$ROOT/core"
SERVICE="/etc/systemd/system/homelab-agent.service"
REPO_URL="${HOMELABV4_REPO_URL:-https://github.com/bacproxmox/homelabv4.git}"
REPO_REF="${HOMELABV4_REPO_REF:-main}"

mkdir -p "$AGENT" "$STATE" "$LOGS" "$CORE"
chmod 700 "$STATE" "$LOGS"

if [[ -f "$AGENT/.payload-manifest.json" ]]; then
  echo "Homelabv4 agent payload manifest:"
  cat "$AGENT/.payload-manifest.json"
  echo
fi

if [[ -f "$AGENT/core/bin/homelab" ]]; then
  echo "Installing bundled Homelab v3 core script payload into $CORE"
  find "$CORE" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
  cp -a "$AGENT/core/." "$CORE/"
elif command -v git >/dev/null 2>&1; then
  if [[ -d "$CORE/.git" ]]; then
    git -C "$CORE" fetch origin "$REPO_REF" || true
    git -C "$CORE" checkout "$REPO_REF" || true
    git -C "$CORE" pull --ff-only origin "$REPO_REF" || true
  else
    git clone -b "$REPO_REF" "$REPO_URL" "$CORE" || true
  fi
fi

find "$AGENT/tasks" -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
find "$AGENT/core" "$CORE" -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
find "$AGENT/core/bin" "$CORE/bin" -type f -exec chmod +x {} \; 2>/dev/null || true

cat > "$SERVICE" <<SERVICE
[Unit]
Description=Homelabv4 localhost agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=HOMELABV4_ROOT=$ROOT
ExecStart=/usr/bin/python3 $AGENT/homelab-agent.py
Restart=on-failure
RestartSec=5
User=root
WorkingDirectory=$AGENT

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now homelab-agent.service
systemctl status homelab-agent.service --no-pager || true

echo "Homelabv4 agent installed on 127.0.0.1:48114"
