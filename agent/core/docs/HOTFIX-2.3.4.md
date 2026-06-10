# Homelab v2.4.4 Hotfix

Bu hotfix gerçek Proxmox testinden çıkan sorunları düzeltir.

## Değişiklikler

- Menü ve banner sürümü `v2.3.5` yapıldı.
- Bootstrap default repo: `bacproxmox/homelabv2.4.4`.
- `/etc/pve/storage.cfg` normalize edildi:
  - disabled `dir: local` bloğu kaldırılır.
  - `btrfs: local-btrfs` veya `btrfs: local-system`, `btrfs: local` yapılır.
- `local:iso/...` kullanımı tekrar güvenli hale getirildi.
- XPG SPECTRIX S40G otomatik `nvme-vm` ZFS pool yapılır.
- TrueNAS diskleri artık kullanıcıdan sorulmaz:
  - tank: `/dev/disk/by-id/ata-TOSHIBA_MG10ACA20TE_4580A0BSF4MJ`
  - private: `/dev/disk/by-id/ata-ST4000NM0053_Z1Z5KNAT`
- VM101 hardware idempotent şekilde enforce edilir:
  - `ide2` TrueNAS ISO
  - `scsi1` tank raw passthrough
  - `scsi2` private raw passthrough
- NVMe scsi1/scsi2 passthrough güvenlik blokajı eklendi.
- TrueNAS API bootstrap eski çalışan v2.2 mimarisine döndürüldü.
- API key yönergesi:

```bash
midclt call api_key.create '{"name":"homelabv23","username":"truenas_admin"}'
```
