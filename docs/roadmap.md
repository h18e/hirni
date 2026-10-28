# hirni – Roadmap

Jede Etappe endet mit etwas, das Raphi auf Mac **und** iPhone ausprobieren kann.
Status: ⬜ offen · 🟡 in Arbeit · ✅ fertig

## Version 1

| # | Etappe | Inhalt | Testbar danach | Status |
|---|---|---|---|---|
| 0 | Fundament | Xcode-27-Projekt (iOS + macOS), Swift Package `HirniKit` mit Tests, iCloud-Container, Signing, `SETUP.md` | App startet auf beiden Geräten (leer) | ✅ |
| 1 | Dateien & Ordner | iCloud-Ordner «hirni», Ordnerbaum, Inbox, Notizen anlegen/umbenennen/löschen, einfacher Texteditor, Zuletzt gelöscht, Sync zwischen Geräten | **Erste echte Nutzung:** Notizen schreiben und auf dem anderen Gerät sehen | ✅ |
| 2 | Ordnen | Verschieben per Drag'n'Drop (Mac) und Wischen/Menü (iPhone), Anpinnen, Duplizieren | Notizen aus der Inbox einsortieren | ✅ |
| 3 | Markdown-Editor | Hervorhebung, Formatierungsleiste iPhone, Tastenkürzel Mac, Checklisten abhaken, `#tags` mit Vorschlägen | Komfortables Schreiben | ✅ |
| 4 | Anhänge | Bilder (Fotos, Kamera, Dateien, Drag'n'Drop) und PDFs, Anzeige in der Notiz | Fotos in Notizen | ✅ |
| 5 | Suche & Tags | Lokaler Such-Index, Volltextsuche, Tag-Liste | Alles wiederfinden | ✅ |
| 6 | Konflikte & Robustheit | Konflikt-Hinweis und -Auflösung, Änderungen von Claude/Finder live übernehmen, Download-Fortschritt | Gleichzeitiges Bearbeiten ohne Datenverlust | ✅ |
| 7 | Datenbank: Grundlagen | Dateiformat festlegen, Felder (alle 7 Typen), Zeilen bearbeiten (Tabelle am Mac, Formular am iPhone) | Erste Datenbank erfassen | ✅ |
| 8 | Datenbank: Tabelle komplett | Mehrere Ansichten, Filter, Sortierung, Gruppierung, Berechnungen pro Spalte, Suche in Datenbanken | Auswertungen in Tabellen | ✅ |
| 9 | Kalender-Ansicht | Monatskalender nach Datumsfeld, Farben nach Auswahlfeld | z. B. Kinder-Weekends | ✅ |
| 10 | Diagramm-Ansicht | Balken/Linie, Gruppierung nach Feld oder Zeitraum, Summe/Anzahl/Durchschnitt | z. B. Ausgaben pro Monat | ✅ |
| 11 | Zeilen-Seiten | Zu jeder Zeile eine Notiz anlegen/öffnen | Details zu einem Eintrag | ✅ |
| 12 | Eingebettete Datenbanken | `hirni-db`-Block in Notizen, interaktive Anzeige im Editor | Datenbank-Ansicht mitten in einer Notiz | ✅ |

## Version 1.1

| # | Teil | Inhalt | Status |
|---|---|---|---|
| A | Teilen aus Hirni | Notiz als PDF (A4, mit Tabellen, Bildern und eingebetteten Datenbanken) oder als Markdown teilen; am Mac «Als PDF exportieren …» | ✅ |
| B | Teilen in Hirni | Hirni im Teilen-Menü anderer Apps: Links, Texte, Fotos landen in der Inbox | ✅ |
| C | Erinnerungen | Benachrichtigung am Stichtag einer Pendenz | ✅ |
| D | Widget und Kurzbefehle | Widget mit offenen Pendenzen, «Neue Notiz» per Siri/Kurzbefehle | ✅ |
| E | Menüleiste am Mac | Schnellnotiz aus der Menüleiste | 🟡 gebaut, Test am Mac offen |
| F | Kalender | Datenbank-Termine in den Apple Kalender übertragen | ⬜ |

## Version 2 (Ideen-Speicher)

- Verknüpfte Notizen `[[…]]` mit Rückverweisen
- Formeln, Verknüpfungen und Rollups zwischen Datenbanken
- Board- und Galerie-Ansicht
- Live-Vorschau im Editor
- Feldtypen Datei/Bild, erstellt/geändert am
- CSV-Import (Bank-Exporte)
- KI-Helfer über Apple Intelligence, eventuell MCP-Server für Claude
