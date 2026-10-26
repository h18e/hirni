# App-Icon

- `AppIcon-Original.png`: Vorlage, 1024 × 1024 px, randlos, ohne Transparenz. Das iPhone rundet die Ecken selbst.
- Der Mac braucht die abgerundete Form mit Rand (sonst setzt macOS 26 das Icon in einen grauen Rahmen). `make-mac-icon.swift` erzeugt sie.

Neues Icon einsetzen (im Ordner `hirni`):

```bash
swift Config/Icon/make-mac-icon.swift Config/Icon/AppIcon-Original.png /tmp/mac-1024.png
cp Config/Icon/AppIcon-Original.png Hirni/Assets.xcassets/AppIcon.appiconset/icon-ios-1024.png
for s in 16 32 128 256 512; do sips -z $s $s /tmp/mac-1024.png --out Hirni/Assets.xcassets/AppIcon.appiconset/icon-mac-$s.png; d=$((s*2)); sips -z $d $d /tmp/mac-1024.png --out Hirni/Assets.xcassets/AppIcon.appiconset/icon-mac-$s@2x.png; done
```
