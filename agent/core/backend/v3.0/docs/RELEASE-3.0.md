# Homelab v3.0

Homelab v3.0 keeps the v2.4.7 backend scripts intact and adds a new Terminal TUI installer layer.

## What changed

- New `installer/v3-tui.sh` Terminal TUI entrypoint.
- `bootstrap.sh` now defaults to `bacproxmox/homelabv3.0` and starts the v3 TUI.
- Existing backend scripts under `bootstrap/`, `vm/`, `services/`, `config/`, `maintenance/`, and `menu/` are preserved.
- Legacy `menu/install-menu.sh` remains available from the v3 TUI.

## v3.0 installer features

- Guided full install / resume.
- Phase/script based progress percentage.
- Per-step log files under `/root/homelab-logs/v3-session-*`.
- Master installer log: `/root/homelab-logs/v3-session-*/00-v3-master.log`.
- Persistent state file: `/root/homelabv3-state/state.tsv`.
- Error handling for critical steps: retry, view log, open legacy menu, or stop.
- Optional steps can be continued as warnings.
- TrueNAS manual install/WebUI/SSH checkpoint remains guided.

## Windows launcher compatibility

The existing Windows launcher can still be used. Enter:

```text
3.0
```

It will target:

```text
https://raw.githubusercontent.com/bacproxmox/homelabv3.0/main/bootstrap.sh
```

Required GitHub repo:

```text
bacproxmox/homelabv3.0
```

## Safety model

v3.0 is intentionally a wrapper/orchestrator release. It does not require adding progress hooks inside the existing backend scripts. The progress bar is based on phase/script weights, not internal command-level progress.
