# Homelab v2.4.4 Hotfix

## Değişiklikler

- Install menu version `v2.3.5` olarak güncellendi.
- `Install selected VM` ana menüden kaldırıldı.
- VM reinstall işlemi maintenance altına taşındı:
  - `maintenance/vm/reinstall-selected-vm.sh`
- Install menu option 4 artık TrueNAS API bootstrap için güvenli prompt gösterir ve ardından VM102-107 kurulumuna geçer.
- Cloudflared token-based kurulum kaldırıldı.
- Cloudflared artık interactive browser auth kullanır:
  - `cloudflared tunnel login`
  - tunnel create/check
  - ingress config generation
  - DNS route creation
  - native systemd service install
- Jellyseerr fresh install Seerr olarak değiştirildi:
  - image: `ghcr.io/seerr-team/seerr:latest`
  - container: `hb-seerr`
  - path: `/opt/homelab/seerr`
  - public route aynı kaldı: `bacneyplus.bacmastercloud.com`
- Seerr readiness helper eklendi.

## Notlar

Cloudflared artık bootstrap sırasında token istemez. Install sırasında Cloudflare login URL'i verir.
