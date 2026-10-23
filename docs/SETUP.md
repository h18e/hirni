# hirni – Ersteinrichtung

Stand nach Etappe 0. Auf deinem MacBook Air ist das meiste schon erledigt. Diese Anleitung brauchst du für das iPhone, oder wenn du hirni auf einem anderen Mac einrichtest.

## Voraussetzungen

| Was | Wert |
|---|---|
| Mac | Apple silicon, macOS 26.6 oder neuer |
| Xcode | 27 oder neuer (App Store) |
| Apple-Account | bezahltes Apple Developer Program (Team «Raphael Hess») |
| iCloud | auf Mac und iPhone mit derselben Apple-ID angemeldet, **iCloud Drive eingeschaltet** |

## 1. Team-Kennung eintragen (einmal pro Mac)

Auf deinem MacBook Air ist das bereits gemacht. Auf einem anderen Mac im Terminal:

```bash
cd ~/Developer/hirni
```

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Danach in `Config/Local.xcconfig` die Kennung `84HTTCD724` statt `HIER_DEINE_TEAM_KENNUNG` eintragen. Diese Datei bleibt lokal und kommt nie ins Git.

## 2. App auf dem Mac starten

1. `Hirni.xcodeproj` doppelklicken. Xcode öffnet sich.
2. Oben in der Mitte der Symbolleiste das Ziel wählen: **Hirni › My Mac**.
3. **⌘R** drücken (Product ▸ Run).
4. Erwartet: Ein Fenster «hirni» mit grünem **«iCloud verbunden»** und einem Pfad darunter.

## 3. App auf dem iPhone starten

1. iPhone per **USB-Kabel** mit dem Mac verbinden und entsperren.
2. Fragt das iPhone «Diesem Computer vertrauen?»: **Vertrauen** wählen und den Code eingeben.
3. Beim ersten Mal muss auf dem iPhone der **Entwicklermodus** aktiv sein:
   iPhone ▸ Einstellungen ▸ Datenschutz & Sicherheit ▸ (ganz unten) **Entwicklermodus** ▸ einschalten. Das iPhone startet danach neu. Nach dem Neustart «Aktivieren» bestätigen.
   (Der Eintrag erscheint erst, wenn das iPhone einmal mit Xcode verbunden war.)
4. In Xcode oben das Ziel wählen: **Hirni › (dein iPhone)**.
5. **⌘R** drücken.
   - Meldet Xcode, das Gerät sei nicht registriert: auf **Register Device** klicken.
   - Beim ersten Mal kann Xcode einige Minuten mit «Preparing iPhone for development» beschäftigt sein. Das ist normal.
6. Erwartet: Die App startet auf dem iPhone mit grünem **«iCloud verbunden»**.

Zeigt die App «iCloud nicht verfügbar»: iPhone ▸ Einstellungen ▸ (dein Name) ▸ iCloud ▸ **iCloud Drive** einschalten.

## 4. Prüfen, ob der iCloud-Ordner sichtbar ist

- **Mac:** Finder ▸ Seitenleiste ▸ **iCloud Drive** ▸ Ordner **hirni**. Darin liegen `Inbox` und `_Zuletzt gelöscht`.
- **iPhone:** App **Dateien** ▸ Durchsuchen ▸ iCloud Drive ▸ **hirni**

Es kann ein paar Minuten dauern, bis der Ordner zum ersten Mal erscheint.

## Im Simulator testen

Im iPhone-Simulator ist meist kein iCloud angemeldet. hirni verwendet dort deshalb automatisch einen lokalen Testordner in der App. Er wird **nicht** synchronisiert. Beim allerersten Start im Simulator kann die Tastatur ein paar Sekunden brauchen, bis sie erscheint.

## Häufige Stolpersteine

| Meldung | Ursache / Lösung |
|---|---|
| «Signing for "Hirni" requires a development team» | `Config/Local.xcconfig` fehlt → Schritt 1 |
| «Device … isn't registered in your developer account» | in Xcode **Register Device** klicken |
| «Developer Mode disabled» | Schritt 3.3 |
| «Untrusted Developer» auf dem iPhone | iPhone ▸ Einstellungen ▸ Allgemein ▸ VPN & Geräteverwaltung ▸ Entwickler-App ▸ **Vertrauen** |
| App zeigt «iCloud nicht verfügbar» | iCloud Drive in den Einstellungen einschalten, mit derselben Apple-ID wie am Mac |
| Ordner «hirni» fehlt im Finder | einige Minuten warten. Hilft das nicht, die App einmal neu starten. |

## Für Claude: Bauen und testen ohne Xcode-Oberfläche

```bash
cd ~/Developer/hirni/HirniKit && swift test
```

```bash
xcodebuild -project Hirni.xcodeproj -scheme Hirni -destination 'platform=macOS' -allowProvisioningUpdates build
```

```bash
xcodebuild -project Hirni.xcodeproj -scheme Hirni -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```
