# Homelab v3.0

Homelab v3.0 is a Terminal TUI installer wrapper over the stabilized Homelab v2.4.7 backend scripts.

## Start from Proxmox

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv3.0/main/bootstrap.sh)
```

## Start from Windows launcher

Use the existing `Start-Homelab-Bootstrap.cmd` / `.ps1` launcher and enter:

```text
3.0
```

The launcher will fetch:

```text
https://raw.githubusercontent.com/bacproxmox/homelabv3.0/main/bootstrap.sh
```

## Main v3.0 change

- Existing backend scripts are preserved.
- New TUI entrypoint: `installer/v3-tui.sh`.
- Legacy menu remains: `menu/install-menu.sh`.

## Logs and state

- Logs: `/root/homelab-logs/v3-session-*`
- Master log: `/root/homelab-logs/v3-session-*/00-v3-master.log`
- State: `/root/homelabv3-state/state.tsv`
