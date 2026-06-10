# Menu hook örneği

Additionals menüsüne basit bir seçenek eklemek istersen:

```bash
apply_bacsflix_jellyfin_branding() {
  bash "$ROOT_DIR/backend/v3.0/additionals/branding/bacsflix-jellyfin/20-apply-bacsflix-jellyfin-branding.sh" apply
}
```

Önerilen menü etiketi:

```text
Branding -> Apply Bacsflix theme to Jellyfin
```
