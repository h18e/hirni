# hirni – Spezifikation

> Stand: 23.10.2026 · Ergebnis der Planungssession (Fragen Q1–Q36).
> **Mit der Umsetzung wird erst begonnen, wenn Raphi «Los» sagt.**

## Rolle

Claude arbeitet als erfahrener Apple-Plattform-Entwickler (Swift, SwiftUI, TextKit, iCloud Drive) und hält Code, Tests und Dokumentation sauber. Raphi gibt die Anforderungen vor, testet und entscheidet. Claude erledigt alle Git-Arbeit.

## Projektname und Zweck

**hirni** ist eine persönliche Notizen- und Datenbank-App für Mac und iPhone und kommt ohne Abo aus. Sie vereint:

- **Apple Notizen:** native Bedienung auf beiden Geräten
- **Obsidian:** offene Markdown-Dateien, auf die Claude direkt zugreifen kann
- **Notion:** Datenbanken mit Auswertungen

Die App ist nur für Raphi gedacht und wird nicht im App Store veröffentlicht.

## Technischer Stack

| Thema | Entscheidung |
|---|---|
| App | Eine SwiftUI-Multiplatform-App (iOS + macOS), gemeinsamer Code |
| Mindest-OS | iOS 26, macOS 26 |
| Entwicklungsumgebung | Xcode 27 (nötig, weil das iPhone auf iOS 27 läuft; Xcode 27 setzt macOS 26.6 und Apple silicon voraus) |
| Bundle ID | `ch.hebera.hirni` |
| iCloud-Container | `iCloud.ch.hebera.hirni` |
| Speicherung | Dateien in iCloud Drive (Ordner «hirni»), **keine** SwiftData/CloudKit-Datenbank |
| Such-Index | lokal pro Gerät (SQLite FTS5 im Cache-Ordner, nicht synchronisiert, jederzeit neu aufbaubar) |
| Diagramme | Swift Charts |
| Editor | TextKit 2 (`UITextView` / `NSTextView`) mit Markdown-Hervorhebung |
| Sprache der Oberfläche | Deutsch |
| Bewusste Einschränkungen | kein eigener Server, keine KI in der App, kein Teilen mit anderen Personen, kein Abo |

### Speicherort und Claude-Zugriff

- Alle Inhalte liegen in **iCloud Drive → hirni** und sind in der Dateien-App und im Finder sichtbar.
- Auf dem Mac liegt dieser Ordner physisch unter `~/Library/Mobile Documents/iCloud~ch~hebera~hirni/Documents/`.
- Claude Code und Claude Desktop lesen und schreiben dort direkt. Neue Dateien von aussen erscheinen automatisch in hirni.
- Der **Quellcode** liegt ausserhalb von iCloud in `~/Developer/hirni`.

## Datenmodell (Dateiformat)

Grundsatz: Alles ist eine normale, menschenlesbare Datei. hirni darf keine Informationen in versteckten Datenbanken halten, die für das Verständnis nötig sind.

```
hirni/
├── Inbox/                    ← neue Notizen landen hier
├── Privat/
│   ├── Ferien/
│   │   ├── Packliste.md
│   │   └── _Anhänge/
│   │       └── foto-2026-10-23.jpg
│   ├── Ausgaben.hirnidb.md   ← Datenbank
│   └── Ausgaben/             ← Zeilen-Seiten dieser Datenbank
│       └── Restaurant Bern.md
└── _Zuletzt gelöscht/
```

### Notiz

- Eine Notiz ist eine `.md`-Datei. **Dateiname = Titel**, also ändert ein neuer Titel auch den Dateinamen.
- Optionaler YAML-Kopf (Frontmatter) für Metadaten, z. B. `angepinnt: true`. Der Editor blendet den Kopf aus und setzt ihn beim Speichern unverändert wieder davor. hirni liest und schreibt nur einfache `schlüssel: wert`-Zeilen, alles andere im Kopf bleibt stehen.
- Anpinnen ändert das Änderungsdatum der Datei nicht.
- Checklisten: `- [ ] offen` / `- [x] erledigt`
- Tags: `#tag` oder `#tag/untertag` irgendwo im Text
- Bilder und PDFs: `![](_Anhänge/foto.jpg)`, abgelegt im Ordner `_Anhänge/` neben der Notiz. Standard-Markdown, damit auch Obsidian sie anzeigt. Dateinamen ohne Leerzeichen (`Foto-20261023-215259.jpg`, bei gleichem Namen `-2`, `-3` …). In Verweisen werden nur Leerzeichen, Klammern und `<>` kodiert, Umlaute bleiben lesbar.
- Wird eine Notiz in einen anderen Ordner verschoben, wandern ihre Anhänge mit. Braucht eine andere Notiz im alten Ordner denselben Anhang, wird er kopiert statt verschoben. Ändert sich dabei ein Dateiname, wird der Verweis angepasst.
- Wird eine Notiz gelöscht, bleiben ihre Anhänge liegen. So funktionieren sie nach dem Wiederherstellen weiter.

### Ordner

- Ordner sind echte Ordner und lassen sich beliebig tief verschachteln.
- `Inbox/` ist ein normaler Ordner mit Sonderstellung: Er steht immer zuoberst und ist das Standardziel für neue Notizen.
- Ordner, die mit `_` oder `.` beginnen, sind Systemordner (z. B. `_Anhänge`, `.obsidian`). Die App blendet sie in der Ordnerliste aus. Eigene Ordner können deshalb nicht mit `_` beginnen.
- Gleiche Namen im selben Ordner bekommen eine Nummer: «Neue Notiz», «Neue Notiz 2» … Die Zeichen `/` und `:` werden in Titeln durch `-` ersetzt.

### Datenbank

- Eine Datenbank ist **eine Datei** `Name.hirnidb.md`.
- **YAML-Kopf:** Schema (Felder mit Typ und Optionen) und gespeicherte Ansichten
- **Inhalt:** eine Markdown-Tabelle, eine Zeile pro Eintrag, mit einer stabilen `id`-Spalte
- Dadurch können Mensch, Claude und Obsidian die Datei lesen. Die genaue Syntax (Escaping von `|`, Darstellung von Mehrfachauswahl, Datumsformat ISO 8601) wird in Etappe 6 festgelegt und hier nachgetragen.
- **Zeilen-Seite:** Zu jeder Zeile lässt sich optional eine Notiz anlegen, im Ordner `Name/` neben der Datenbank. Im Frontmatter steht `hirni-zeile: <id>`.
- **Eingebettete Ansicht in einer Notiz:** ein Codeblock, der in anderen Programmen lesbar bleibt:

  ````
  ```hirni-db
  datenbank: Ausgaben
  ansicht: Pro Monat
  ```
  ````

#### Feldtypen (Version 1)

| Typ | Beschreibung |
|---|---|
| Text | einzeilig |
| Zahl | Format: normal, Währung (CHF, EUR, …), Prozent |
| Auswahl | genau ein Wert aus einer Liste mit Farben |
| Mehrfachauswahl | mehrere Werte (Tags) |
| Datum | Datum, optional mit Uhrzeit und optional als Zeitraum |
| Checkbox | ja/nein |
| URL | Link |

#### Ansichten (Version 1)

Jede Ansicht hat einen Namen und eigene **Filter**, **Sortierung** und **Gruppierung**.

| Ansicht | Inhalt |
|---|---|
| Tabelle | Spalten ein- und ausblenden. Pro Spalte eine Berechnung: Summe, Durchschnitt, Anzahl, Min, Max |
| Kalender | Einträge auf einem Monatskalender, nach einem Datumsfeld, farbig nach einem Auswahlfeld |
| Diagramm | Balken oder Linie. X-Achse = Feld (Auswahl, oder Datum nach Tag/Woche/Monat/Jahr), Y-Achse = Anzahl oder Summe/Durchschnitt eines Zahlenfelds, optional aufgeteilt nach einem Auswahlfeld |

### Zuletzt gelöscht

- Gelöschte Notizen, Ordner und Datenbanken werden nach `_Zuletzt gelöscht/` verschoben und lassen sich von dort wiederherstellen.
- Jedes gelöschte Element bekommt eine eigene Hülle `_Zuletzt gelöscht/<Zeitstempel>-<Kennung>/`. Darin liegen das Element selbst und eine versteckte Datei `.hirni-geloescht.json` mit dem ursprünglichen Pfad (`originalPath`) und dem Löschdatum (`deletedAt`, ISO 8601). So kommen sich gleichnamige Notizen aus verschiedenen Ordnern nicht in die Quere.
- Was ohne diese Begleitinfo im Papierkorb liegt (z. B. im Finder hineingezogen), wird beim Wiederherstellen in die Inbox gelegt, Ordner in die oberste Ebene.
- Ist der ursprüngliche Name beim Wiederherstellen belegt, bekommt das Element eine Nummer («Einkauf 2»). Fehlt der ursprüngliche Ordner, wird er neu angelegt.
- Nach 30 Tagen räumt hirni automatisch auf.

## Funktionale Anforderungen (Version 1)

### Navigation und Aufbau

- **Mac:** drei Spalten (Ordner | Liste | Inhalt). In der Seitenleiste stehen Inbox, Ordnerbaum, Tags und «Zuletzt gelöscht».
- **iPhone:** dieselbe Hierarchie zum Durchtippen. Die App startet direkt in der Inbox. Der Knopf **Neue Notiz** (Stift oben rechts, am Mac auch ⌘N) legt die Notiz im gerade offenen Ordner an, also standardmässig in der Inbox.
- **Notizliste:** sortiert nach «zuletzt geändert». Angepinnte Notizen stehen oben. Jede Zeile zeigt Titel, Vorschau und Datum.

### Ordner

- anlegen, umbenennen, löschen, verschachteln
- **Verschieben:** am Mac per Drag'n'Drop (Notizen und Ordner auf einen Ordner oder die Inbox in der Seitenleiste). Überall auch per Kontextmenü «Verschieben nach …» mit Ordnerauswahl, auf dem iPhone zusätzlich per Wischen nach rechts. Ein Ordner kann nicht in sich selbst verschoben werden. Ist der Name am Ziel belegt, gibt es eine Nummer.
- Drag'n'Drop verwendet einen eigenen Datentyp (`ch.hebera.hirni.item`), keine Datei-URL. So kann man eine Notiz nicht aus Versehen auf den Schreibtisch und damit aus iCloud herausziehen.

### Notizen und Editor

- **Grundfunktionen:** anlegen, umbenennen, löschen, anpinnen, duplizieren («Titel Kopie», nicht angepinnt)
- **Markdown-Hervorhebung:** Die Syntax bleibt sichtbar, aber grau. Überschriften (1–6), fett, kursiv, durchgestrichen, Listen, Checklisten, Zitate, Inline-Code, Codeblöcke, Links und Tags werden gestaltet. Gerade Anführungszeichen und Bindestriche bleiben erhalten (keine automatische Ersetzung).
- **iPhone:** Formatierungsleiste über der Tastatur: Überschrift, fett, kursiv, Liste, Checkliste, Tag, Tastatur ausblenden. Der Knopf für Bilder folgt in Etappe 4.
- **Mac:** Knöpfe in der Fensterleiste mit Tastenkürzeln: Überschrift ⇧⌘H, fett ⌘B, kursiv ⌘I, Liste ⇧⌘8, Checkliste ⇧⌘L
- **Überschrift-Knopf:** wechselt reihum keine → `#` → `##` → `###` → keine
- **Listen:** Liste und Checkliste lassen sich auch auf einer leeren Zeile beginnen. Return setzt sie fort, Return in einem leeren Punkt beendet sie.
- **Checklisten:** ein Tipp bzw. Klick auf `[ ]` hakt ab, erledigte Punkte erscheinen durchgestrichen
- **Tags:** Nach `#` erscheinen passende Tags aus dem ganzen hirni-Ordner (die häufigsten zuerst) und aus der offenen Notiz, auch eben erst getippte. Auf dem iPhone in der Leiste, am Mac unter dem Text, dort übernimmt Tab den ersten Vorschlag. Tags dürfen Buchstaben (auch Umlaute), Ziffern, `_`, `-` und `/` enthalten, aber nicht nur aus Ziffern bestehen (wie bei Obsidian).
- **Bilder und PDFs einfügen:** iPhone über die Büroklammer in der Leiste (Foto-Mediathek, bis 10 Fotos auf einmal, Kamera, Datei). Mac über die Büroklammer in der Fensterleiste (⇧⌘A) oder per Drag'n'Drop einer Datei in den Text. Fotos werden als JPEG mit höchstens 3000 Pixeln gespeichert. Standortdaten und andere Metadaten werden dabei entfernt. HEIC-Dateien werden in JPEG umgewandelt.
- **Anzeige:** Bilder und die erste PDF-Seite erscheinen direkt unter ihrer Zeile (Bilder höchstens 360 Punkte hoch, PDFs 260). Der Verweis selbst bleibt klein und grau sichtbar. Fehlt die Datei, erscheint ein Hinweis-Symbol. Antippen bzw. Klicken öffnet die Vorschau (QuickLook).
- **Notizliste:** Anhänge erscheinen in der Vorschau als `[Bild]` bzw. `[PDF]`.
- **Noch nicht:** Bild einfügen per Einsetzen (⌘V) und Drag'n'Drop auf dem iPhone.
- **Speichern:** automatisch, ohne Speichern-Knopf

### Tags und Suche

- **Tags:** Die Tag-Liste in der Seitenleiste zeigt alle Tags. Ein Tipp listet alle Notizen mit diesem Tag.
- **Volltextsuche:** über Notizen und Datenbank-Inhalte. Treffer werden hervorgehoben, filterbar nach Ordner.

### Datenbanken

- Datenbank anlegen, Felder hinzufügen, umbenennen, Typ ändern (mit Warnung bei Datenverlust), umsortieren und löschen
- Zeilen anlegen, bearbeiten und löschen
- **Mac:** direkt in der Tabelle bearbeiten
- **iPhone:** Zeile antippen → Formular
- Ansichten anlegen, umbenennen und wechseln, Filter, Sortierung und Gruppierung einstellen
- Tabelle, Kalender und Diagramm wie im Datenmodell beschrieben
- Zeilen-Seite öffnen bzw. anlegen
- Ansicht in eine Notiz einbetten, interaktiv angezeigt mitten im Text

### Sync und Konflikte

- hirni überwacht den iCloud-Ordner und zeigt Änderungen von anderen Geräten oder von Claude automatisch an.
- Dateien, die auf dem iPhone noch nicht heruntergeladen sind, lädt hirni beim Öffnen nach und zeigt dabei einen Fortschritt.
- **Konflikt** (dieselbe Datei auf zwei Geräten geändert): Hinweis «2 Versionen vorhanden». Raphi wählt eine Version oder behält beide als separate Dateien.
- **Datenbank-Konflikte:** Wo möglich werden sie automatisch Zeile für Zeile zusammengeführt (über die `id`). Nur echte Konflikte in derselben Zeile werden nachgefragt.

## Ausserhalb von Version 1

- **Version 1.1:** Schnellerfassung (Widget, Teilen-Menü, Menüleiste am Mac, Kurzbefehle/Siri) und Benachrichtigungen. Termine aus Datenbanken in den Apple Kalender übertragen.
- **Version 2:** verknüpfte Notizen `[[…]]` mit Rückverweisen, Formeln, Verknüpfungen und Rollups zwischen Datenbanken, Board- und Galerie-Ansicht, Live-Vorschau im Editor (Syntax ausblenden), Feldtypen Datei/Bild und «erstellt/geändert am», CSV-Import, KI-Helfer über Apple Intelligence, eventuell ein MCP-Server für Claude
- **Bewusst nicht geplant:** App Store, Teilen mit anderen Personen, Handschrift

## Umsetzungshinweise

- **Struktur:**
  - Logik in einem eigenen Swift Package **`HirniKit`**: Dateiformat lesen und schreiben, Datenbank-Engine (Filter, Sortierung, Gruppierung, Berechnungen), Such-Index, Konflikt-Zusammenführung. Das Package hat keine Abhängigkeit zu SwiftUI und ist vollständig mit Unit-Tests abgedeckt.
  - Das App-Target enthält nur die Oberfläche (SwiftUI) und die Plattform-Anbindung: Dateizugriff mit `NSFileCoordinator`, Änderungsüberwachung mit `NSMetadataQuery`.
- **Robustheit:** Dateien, die hirni nicht versteht, werden nie verändert oder gelöscht. Fehlerhaftes YAML oder kaputte Tabellen werden angezeigt, nicht «repariert».
- **Fremde Bearbeitung:** Änderungen von Claude oder anderen Programmen an offenen Dateien werden erkannt. Ungespeicherte Eingaben gehen dabei nie verloren.
- **Formatwechsel:** Jede Änderung am Dateiformat wird hier in der Spec nachgeführt.
- **Lebende Dokumente:** `README.md` (Aufbau), `docs/SETUP.md` (Ersteinrichtung Schritt für Schritt), `docs/roadmap.md` (Etappen mit Status). Sie werden bei jeder relevanten Änderung aktualisiert.
- **Git:** Claude macht alle Commits. Persönliche Einstellungen wie das Signing-Team kommen in eine lokale, von Git ignorierte Config-Datei.
- **Nach jeder Etappe:** Claude baut für beide Plattformen per `xcodebuild` und lässt die Tests laufen. Raphi testet die Bedienung auf Mac und iPhone.
