# Homelab v2.4.5-r3

This build focuses on the installer regressions found after the v2.4.5-r2 manual 1→9 test.

## Root causes addressed

1. `nvme-vm-two` detection still missed the MLD/MDL M500 NVMe even though the disk was visible in hardware logs.
2. Manual menu option 3 still printed the old TrueNAS workflow instead of entering the new "TrueNAS kurulumu bitti mi?" checkpoint.
3. PBS installation/configuration could stall during NFS mount and failed package updates because the PBS enterprise repository was disabled too late.
4. PBS reachability validation treated HTTP 401 as service failure, even though 401/403 can mean PBS is reachable and asking for authentication.
5. VM107 disk sizing left too little free space on `nvme-vm-two`.

## Main fixes

### Storage / MLD M500 detection

`bootstrap/02-normalize-local-storage.sh` now uses multiple detection paths:

- `/dev/disk/by-id` matching `MLD`, `MDL`, or `M500`.
- `/sys/block/nvme*/device/model` and serial.
- `lsblk -P` quoted field parsing.
- optional `nvme list` fallback.
- last-resort single unused ~1TB NVMe fallback.

If `nvme-vm-two` already exists in Proxmox storage, disk detection and wipe logic are skipped completely.

### TrueNAS manual checkpoint

Menu option 3 now runs:

1. VM101 creation/update.
2. VM101 installer start.
3. `TrueNAS kurulumu bitti mi?` prompt.
4. ISO removal + disk boot switch.
5. WebUI reachability loop.
6. SSH validation loop.

Guided pipeline and manual option 3 now share the same checkpoint function.

### PBS fixes

- PBS enterprise repositories are disabled before the first `apt-get update` inside VM110.
- Deb822 `.sources` files are handled with `Enabled: no`.
- PBS NFS mount is bounded with a 45-second timeout instead of hanging for many minutes.
- Existing `.chunks` datastores are registered instead of recreated destructively.
- Large recursive `chown -R` over the PBS datastore is avoided.
- PBS API validation accepts HTTP `200`, `401`, or `403` as "proxy reachable"; auth is handled separately.
- PVE PBS storage creation uses the real password value instead of passing a temporary filename as the password.

### VM107 sizing

VM107 now leaves a default 64 GiB free reserve on `nvme-vm-two` instead of 30 GiB.

## Fresh install command after publishing

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv2.4.5/main/bootstrap.sh)
```

## Manual test focus

During the next test, watch these points first:

1. Option 12 / normalize storage should either detect MLD/MDL M500 or skip because `nvme-vm-two` already exists.
2. Option 3 should show `TrueNAS kurulumu bitti mi?` after creating VM101.
3. PBS install should not hit `enterprise.proxmox.com/debian/pbs` 401 before repo disable.
4. PBS mount should fail quickly with a clear message if Raspberry Pi NFS is unavailable, not wait silently for minutes.
5. VM106 services should stay healthy because VM106 now lands on `nvme-vm-two`.
