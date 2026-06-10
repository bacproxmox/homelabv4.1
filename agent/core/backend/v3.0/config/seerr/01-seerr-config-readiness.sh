#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "seerr-readiness"
source "$ROOT_DIR/utils/remote.sh"
TMP="$(mktemp -d)"
cat > "$TMP/seerr-readiness.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
echo "🔎 Seerr container:"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'hb-seerr|NAMES' || true
mkdir -p /opt/homelab/seerr
cat > /opt/homelab/seerr/SEERR_POLICY.txt <<'POLICY'
Homelab v2.4.7 Seerr policy:
- Seerr runs on VM102:5055
- Public route remains bacneyplus.bacmastercloud.com
- API route remains bacneyplus-api.bacmastercloud.com
- Use Jellyfin as media server backend
- bacmaster should be the highest/admin user
- Fresh installs use ghcr.io/seerr-team/seerr:latest
POLICY
echo "✅ Seerr readiness/policy yazıldı"
EOS
chmod +x "$TMP/seerr-readiness.sh"
rscp "$TMP/seerr-readiness.sh" 102 /tmp/hv236-seerr-readiness.sh
rssh 102 "sudo bash /tmp/hv236-seerr-readiness.sh"
