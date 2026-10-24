# hirni

Persönliche Notizen- und Datenbank-App für Mac und iPhone, synchronisiert über iCloud Drive.
Notizen sind Markdown-Dateien, Datenbanken funktionieren wie in Notion, und Claude kann direkt auf alle Dateien zugreifen.

- [Spezifikation](docs/spec.md) – was hirni kann und wie die Dateien aufgebaut sind
- [Roadmap](docs/roadmap.md) – Etappen und Stand
- [Ersteinrichtung](docs/SETUP.md) – App auf Mac und iPhone starten

## Aufbau

| Ordner | Inhalt |
|---|---|
| `Hirni/` | App für iOS und macOS (SwiftUI). Neue Dateien hier landen automatisch im Projekt. |
| `Hirni/Editor/` | Markdown-Editor: Textansicht, Hervorhebung, Formatierungsleiste, Bildanzeige, Anhang-Auswahl |
| `Hirni/Database/` | Datenbanken: Tabelle (Mac), Liste und Formular (iPhone), Felder-Verwaltung |
| `HirniKit/` | Swift Package mit der gesamten Logik ohne Oberfläche, getestet mit `swift test` |
| `Config/` | Info.plist, Berechtigungen (iCloud), Signierung |
| `docs/` | Spezifikation, Roadmap, Einrichtung |

Die Notizen selbst liegen nicht hier, sondern in **iCloud Drive → hirni**
(auf dem Mac: `~/Library/Mobile Documents/iCloud~ch~hebera~hirni/Documents/`).

Status: Etappe 9 (Kalender-Ansicht) gebaut, Test auf den Geräten offen.
