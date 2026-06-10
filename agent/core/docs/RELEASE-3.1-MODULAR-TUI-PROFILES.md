# Homelab v3.1 Modular TUI Profiles Update

## What changed

- Added `tasks/bootstrap/collect-install-preferences.sh` so theme, branding and avatar URL choices are collected at the start of guided install.
- Changed guided TUI execution to render a live terminal progress dashboard instead of showing an OK dialog before every manifest step.
- Added Jellyfin theme automation with choices for Bacsflix, Finimalism, ElegantFin, Better Jellyfin UI, Abyss, or no custom CSS.
- Added profile/avatar automation tasks for Jellyfin/Bacsflix, Seerr/Bacneyplus and Nextcloud/Bacscloud.
- Added `flows/config/core-config-with-branding.sh` so core config, theme application and profile automation run together after service installs.
- Legacy profile/theme wrappers now call the new v3.1 modular tasks.

## Preference file

The guided install writes:

```text
/root/homelab-secrets/install-preferences.env
```

Useful keys:

```text
JELLYFIN_THEME=bacsflix
JELLYFIN_BRAND=Bacsflix
SEERR_BRAND=Bacneyplus
NEXTCLOUD_BRAND=Bacscloud
BACMASTER_AVATAR_URL=...
ATLON_AVATAR_URL=...
ELIFEZEL_AVATAR_URL=...
TULUMBA_AVATAR_URL=...
```

Set `HOMELAB_FORCE_PREFERENCES=1` before running the preferences task if you want to answer these again.
