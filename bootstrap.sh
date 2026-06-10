#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${HOMELABV4_ROOT:-/opt/homelabv4}"
AGENT="$ROOT/agent"
REPO_URL="${HOMELABV4_REPO_URL:-https://github.com/bacproxmox/homelabv4.git}"
REPO_REF="${HOMELABV4_REPO_REF:-main}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Homelabv4 bootstrap must run as root on the Proxmox host." >&2
  exit 1
fi

echo "Homelabv4 bootstrap"
echo "Repo: $REPO_URL"
echo "Ref : $REPO_REF"
echo "Root: $ROOT"

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git python3 rsync openssh-client
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command is missing: $1" >&2
    exit 2
  }
}

need_cmd git
need_cmd python3
need_cmd rsync

TMP="$(mktemp -d /tmp/homelabv4-bootstrap.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Homelabv4 source..."
git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$TMP/repo"

if [[ ! -f "$TMP/repo/agent/install-agent.sh" ]]; then
  echo "agent/install-agent.sh not found in the downloaded repository." >&2
  exit 3
fi

mkdir -p "$AGENT"
rsync -a --delete "$TMP/repo/agent/" "$AGENT/"
chmod +x "$AGENT/install-agent.sh"
find "$AGENT/tasks" "$AGENT/core" -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
find "$AGENT/core/bin" -type f -exec chmod +x {} \; 2>/dev/null || true

echo "Installing localhost agent..."
HOMELABV4_REPO_URL="$REPO_URL" HOMELABV4_REPO_REF="$REPO_REF" bash "$AGENT/install-agent.sh"

cat <<EOF

Homelabv4 bootstrap completed.

Next steps:
1. Open the Homelabv4 Windows app.
2. Connection > Host: this Proxmox IP, root password.
3. Click Open Tunnel.
4. Use Install or Scripts to run VM/service/config tasks.

CLI fallback:
  /opt/homelabv4/core/bin/homelab list
  /opt/homelabv4/core/bin/homelab run tasks/vm/106-media-ai-vm-install.sh

Agent API listens only on:
  http://127.0.0.1:48114
EOF
