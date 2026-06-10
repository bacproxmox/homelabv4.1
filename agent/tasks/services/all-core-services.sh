#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "$0")/../lib/core-bridge.sh"
run_core "tasks/services/common/prepare-all-docker-hosts.sh"
run_core "tasks/services/arr/install.sh"
run_core "tasks/services/seerr/install.sh"
run_core "tasks/services/uptime-kuma/install.sh"
run_core "tasks/services/nextcloud/install.sh"
run_core "tasks/services/jellyfin/install.sh"
run_core "tasks/services/immich/install.sh"
run_core "tasks/services/ollama/install.sh"
run_core "tasks/services/lidarr/install.sh"
run_core "tasks/services/homeassistant/install.sh"
run_core "tasks/services/pbs/install.sh"
