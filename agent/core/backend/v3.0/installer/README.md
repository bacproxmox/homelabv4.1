# Homelab v3.0 Terminal Installer

Run from the repository root as root:

```bash
bash installer/v3-tui.sh
```

The TUI calls the existing Homelab backend scripts and stores v3 session logs in:

```text
/root/homelab-logs/v3-session-YYYYMMDD-HHMMSS/
```

State is stored in:

```text
/root/homelabv3-state/state.tsv
```

The legacy menu remains available:

```bash
bash menu/install-menu.sh
```
