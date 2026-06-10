# Homelab v3.1 Terminal Installer

The v3.1 installer entrypoint is `installer/tui.sh`.

It reads guided install steps from `manifests/guided-steps.tsv` and dispatches each step through `bin/homelab run <target>`.

Legacy `installer/v3-tui.sh` remains as a wrapper for compatibility.
