# Homelabv4

Homelabv4 is a Windows Electron control panel for a fresh Proxmox install. The app bootstraps a localhost-only Proxmox agent over SSH, then manages install steps, hardware inventory, health checks, repair tasks, support bundles, and Bacmaster Branding Packs from one desktop UI.

## Current implementation

- Electron + React + TypeScript desktop app.
- Windows Credential Manager profile/secret storage through `keytar`, with Electron `safeStorage` as migration/fallback storage.
- SSH bootstrap and localhost tunnel support through `ssh2`.
- Proxmox `homelab-agent` Python service payload under `agent/`.
- Agent API for health, manifest, state, runs, hardware inventory, support bundles, and branding packs.
- Imported Homelab v3.1.1-r2 script payload under `agent/core`, installed to `/opt/homelabv4/core` during bootstrap.
- Script Center catalog for grouped and single-script execution, including dynamic discovery of v3 VM, service, config, maintenance, flow, and additional scripts.
- GitHub Packages panel for scanning `bacproxmox/homelabv*` repositories, creating a version repository such as `homelabv4.1`, and committing ZIP contents into it.
- Branding pack manifest with BacStatus, BacsCloud, Bacsflix, Bacmaster's NAS, BacmastersAI, BacHome, BacPhotos, BacMusic, Bacneyplus, BacChia, and Bacmaster app identity.
- Vendor wrappers for the supplied Nextcloud, Jellyfin, TrueNAS, OpenWebUI, and Immich branding packages.
- Planned hooks for Uptime Kuma, Home Assistant, BacMusic/Lidarr, Bacneyplus/Seerr, BacChia VM107, and app-shell branding.

## Development

```powershell
npm install
npm run dev
```

Production renderer preview, useful for visual smoke tests without launching Electron:

```powershell
npx vite out/renderer --host 127.0.0.1 --port 4174 --strictPort
```

## Build

```powershell
npm run build
npm run dist
```

## GitHub Packages

The `Packages` tab can scan Homelab version repositories such as:

```text
github.com/bacproxmox/homelabv2.4.5
github.com/bacproxmox/homelabv3.1.1-r2
github.com/bacproxmox/homelabv4.1
```

Matching repositories appear as selectable labels like `Homelabv2.4.5`. Select a source package such as `homelabv4.1.zip`, enter or save a GitHub token with repository creation and contents access, then publish the ZIP contents into the selected or newly named repository.

## Agent

The Windows app uploads `agent/` to:

```text
/opt/homelabv4/agent
```

The agent binds to:

```text
127.0.0.1:48114
```

Electron reaches it through an SSH tunnel; the port is not exposed to the LAN.

## Fresh Proxmox Install

Recommended Windows panel flow:

1. Install/open `Homelabv4.exe` on Windows.
2. Enter the Proxmox IP and fresh `root` password in Connection.
3. Click `Bootstrap Agent`.
4. Click `Open Tunnel`.
5. Use `Install` for the guided flow or `Scripts` for single VM/service/config scripts.

CLI fallback from the Proxmox shell:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv4/main/bootstrap.sh)
```

After that, open the Windows panel and click `Open Tunnel`. The old-style script runner is also available on Proxmox:

```bash
/opt/homelabv4/core/bin/homelab list
/opt/homelabv4/core/bin/homelab run tasks/vm/106-media-ai-vm-install.sh
```
