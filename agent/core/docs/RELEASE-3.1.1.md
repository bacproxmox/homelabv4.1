# Homelab v3.1.1-r2 - Stabilization Release

v3.1.1 is a stabilization pass over v3.1 modular TUI. It does not rewrite the backend; it fixes the resume/retry and TrueNAS/Cloudflared recovery problems found during the 2026-05-29 install test.

## Fixes

- TUI state handling: `warn` is no longer treated as complete. Only `done` and `skipped` are complete, so warning steps stay retryable on resume.
- Cloudflared prepare: if Cloudflare already has the configured tunnel but the local tunnel JSON credential is missing, the installer offers recovery choices: create a new tunnel name, retry after deleting the stale tunnel, or skip Cloudflared for now. This flow still uses `cloudflared tunnel login`; it does not ask for a Cloudflare API token.
- Cloudflared final setup is non-critical in the guided manifest so remote-access setup cannot block an otherwise healthy local install.
- TrueNAS checkpoint flow now checks WebUI/SSH first. If the checkpoint is already complete, VM create/ISO/disk validation is skipped on resume.
- TrueNAS disk preflight now prints clear recovery commands when the expected private disk is missing and never auto-selects a replacement disk.
- Optional `TRUENAS_PRIVATE_REQUIRED=0` tank-only mode was added for conscious recovery installs.
- TrueNAS pool import now captures/polls middleware job IDs where available and prints job failure detail instead of only saying the pool did not become active.
- Support bundle now includes v3 state files, VM configs, `pvesm status`, detailed `lsblk`, `/dev/disk/by-id`, and relevant `dmesg` disk errors.
- Hardware preflight NVMe temperature parsing now uses `nvme smart-log -o json` where possible and avoids impossible values such as `98310C`.

## Notes

- Default behavior still expects both `tank` and `private` pools. Use `TRUENAS_PRIVATE_REQUIRED=0` only when you intentionally want a tank-only recovery/install.
- Existing legacy backend paths remain in `backend/v3.0` for compatibility.
