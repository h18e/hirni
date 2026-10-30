# hirni – Spezifikation

> Stand: 23.10.2026 · Ergebnis der Planungssession (Fragen Q1–Q36).
> **Mit der Umsetzung wird erst begonnen, wenn Raphi «Los» sagt.**

## Rolle

Claude arbeitet als erfahrener Apple-Plattform-Entwickler (Swift, SwiftUI, TextKit, iCloud Drive) und hält Code, Tests und Dokumentation sauber. Raphi gibt die Anforderungen vor, testet und entscheidet. Claude erledigt alle Git-Arbeit.

## Projektname und Zweck

Der App-Name lautet «Hirni» (Anzeige unter dem Symbol, im Dock, in iCloud Drive und in der App). Technische Kennungen bleiben klein: Bundle-ID `ch.hebera.hirni`, iCloud-Container `iCloud.ch.hebera.hirni` und die Kennzeichen in den Dateien (`hirni-datenbank`, `hirni-db`, `hirni-zeile`). Sie dürfen sich nie ändern, sonst findet die App ihre Daten nicht mehr.

**Hirni** ist eine persönliche Notizen- und Datenbank-App für Mac und iPhone und kommt ohne Abo aus. Sie vereint:

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
├── Vorlagen/                 ← Vorlagen für neue Notizen und Zeilen-Seiten
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

- Eine Datenbank ist **eine Datei** `Name.hirnidb.md`. Sie erscheint in der Notizliste ihres Ordners mit Tabellen-Symbol und «Datenbank · N Einträge».
- **Format** (verbindlich, so dürfen auch Claude und andere Programme schreiben):

  ```
  ---
  hirni-datenbank: 1
  felder:
    - {"name": "Name", "typ": "text"}
    - {"name": "Betrag", "typ": "zahl", "format": "chf"}
    - {"name": "Kategorie", "typ": "auswahl", "optionen": ["Essen", "Reisen"]}
    - {"name": "Datum", "typ": "datum", "zeit": true}
  ---
  Optionaler Text vor der Tabelle.

  | id | Name | Betrag | Kategorie | Datum |
  |---|---|---|---|---|
  | k3f9a2c1 | Pizza | 42.5 | Essen | 2026-10-24 19:30 |
  ```

  - **Kopf:** `hirni-datenbank: 1` kennzeichnet die Datei. Unter `felder:` steht pro Feld eine Zeile mit einem JSON-Objekt. Das ist gültiges YAML und lässt sich leicht lesen und schreiben. Schlüssel: `name`, `typ` (`text`, `zahl`, `auswahl`, `mehrfachauswahl`, `datum`, `checkbox`, `url`), optional `format` (`normal`, `chf`, `eur`, `usd`, `prozent`), `optionen` (Liste) und `zeit` (Datum mit Uhrzeit). Weitere Kopfzeilen bleiben unverändert erhalten.
  - **Tabelle:** Die erste Spalte heisst `id` (8 Zeichen, zufällig). Die weiteren Spalten tragen die Feldnamen, ihre Reihenfolge ist egal. Ein `|` in einem Wert wird als `\|` geschrieben, ein Zeilenumbruch als `<br>`. Text vor und nach der Tabelle bleibt erhalten.
  - **Werte** (ohne Ländereinstellung): Zahl `42.5` (beim Lesen geht auch `42,50`, `CHF 1'200` oder `12 %`), Prozent als `12` für 12 %, Datum `2026-10-24` oder `2026-10-24 14:30`, Zeitraum `2026-10-24/2026-10-26` (beim Lesen auch `24.10.2026`), Checkbox `ja`/`nein`, Mehrfachauswahl `Ferien, Kinder` (Optionen ohne Komma).
  - **Ansichten** stehen unter `ansichten:`, ebenfalls eine JSON-Zeile pro Ansicht: `name`, `typ` (`tabelle`, `liste`, `kalender`, `diagramm`), optional `filter` (Liste aus `feld`, `bedingung`, `wert`), `sortierung` (Liste aus `feld`, `absteigend`), `gruppierung` (Feldname), `berechnungen` (Feldname → `anzahl`, `summe`, `durchschnitt`, `min`, `max`), `ausgeblendet` (Feldnamen), für Kalender `datumsfeld` und `farbfeld`, für Diagramme `diagramm` mit `art` (`balken`, `linie`), `x` (Feld der waagrechten Achse), `zeitraster` (`tag`, `woche`, `monat`, `jahr`, nur bei Datumsfeldern), `y` (`anzahl`, `summe`, `durchschnitt`), `wert` (Zahlenfeld für Summe/Durchschnitt) und optional `aufteilen` (Auswahl-, Mehrfachauswahl- oder Checkbox-Feld). Bedingungen: `ist`, `ist nicht`, `enthält`, `enthält nicht`, `ist leer`, `ist nicht leer`, `>`, `<`, `≥`, `≤`, `vor`, `nach`, `angehakt`, `nicht angehakt`. Eine unlesbare Ansicht wird übersprungen, die Daten bleiben sichtbar.
  - **Robust:** Werte, die nicht zum Feldtyp passen, bleiben unverändert stehen und werden so angezeigt. Spalten ohne Feld im Kopf (z. B. von Hand ergänzt) werden zu Textfeldern. Zeilen ohne oder mit doppelter `id` bekommen eine neue. Eine Datei mit unlesbarem Kopf wird angezeigt, aber nicht verändert.
- **Zeilen-Seite:** Zu jeder Zeile lässt sich optional eine Notiz anlegen, im Ordner `Name/` neben der Datenbank. Im Frontmatter steht `hirni-zeile: <id>`.
  - Die Zuordnung läuft nur über die `id`. Die Seite darf umbenannt werden, und Claude kann Seiten selbst anlegen (Notiz mit diesem Kopf im Ordner). Gibt es zu einer `id` mehrere Seiten, gilt die alphabetisch erste.
  - Neue Seiten heissen wie die Zeile (erstes Feld), sonst «Eintrag». Bei gleichem Namen gibt es eine Nummer.
  - Wird die Datenbank umbenannt oder verschoben, zieht der Ordner mit, falls der neue Name frei ist.
  - Wird eine Zeile oder die Datenbank gelöscht, bleiben die Seiten als normale Notizen stehen.
- **Eingebettete Ansicht in einer Notiz:** ein Codeblock, der in anderen Programmen lesbar bleibt:

  ````
  ```hirni-db
  datenbank: Ausgaben
  ansicht: Pro Monat
  ```
  ````

  - `datenbank`: Name der Datenbank oder Pfad ab dem hirni-Ordner (`Privat/Ausgaben`). Ohne Pfad wird zuerst im Ordner der Notiz gesucht, dann im ganzen hirni-Ordner (kürzester Pfad zuerst).
  - `ansicht`: optional, sonst die erste Ansicht. Filter, Sortierung und Darstellung kommen von dieser Ansicht.
  - In der Notizliste erscheint der Block als «[Datenbank: Ausgaben]».

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
| Liste | Kompakt: pro Eintrag eine Zeile mit dem ersten Feld als Titel und den nächsten drei Werten darunter. Gruppen und Berechnungen wie in der Tabelle. Auf dem iPhone Wischen nach links (löschen) und rechts (Seite) |
| Kalender | Einträge auf einem Monatskalender, nach einem Datumsfeld, farbig nach einem Auswahlfeld |
| Diagramm | Balken oder Linie. X-Achse = Feld (Auswahl, oder Datum nach Tag/Woche/Monat/Jahr), Y-Achse = Anzahl oder Summe/Durchschnitt eines Zahlenfelds, optional aufgeteilt nach einem Auswahlfeld (gestapelte Balken bzw. eine Linie pro Option, Farben wie im Kalender). Leere Zeitabschnitte zählen bei Anzahl und Summe als 0, beim Durchschnitt fehlen sie. Filter der Ansicht gelten auch fürs Diagramm |

### Zuletzt gelöscht

- Gelöschte Notizen, Ordner und Datenbanken werden nach `_Zuletzt gelöscht/` verschoben und lassen sich von dort wiederherstellen.
- Jedes gelöschte Element bekommt eine eigene Hülle `_Zuletzt gelöscht/<Zeitstempel>-<Kennung>/`. Darin liegen das Element selbst und eine versteckte Datei `.hirni-geloescht.json` mit dem ursprünglichen Pfad (`originalPath`) und dem Löschdatum (`deletedAt`, ISO 8601). So kommen sich gleichnamige Notizen aus verschiedenen Ordnern nicht in die Quere.
- Was ohne diese Begleitinfo im Papierkorb liegt (z. B. im Finder hineingezogen), wird beim Wiederherstellen in die Inbox gelegt, Ordner in die oberste Ebene.
- Ist der ursprüngliche Name beim Wiederherstellen belegt, bekommt das Element eine Nummer («Einkauf 2»). Fehlt der ursprüngliche Ordner, wird er neu angelegt.
- Nach 30 Tagen räumt hirni automatisch auf.
- «Alle löschen» (Papierkorb-Knopf oben) leert «Zuletzt gelöscht» sofort ganz, nach einer Rückfrage mit der Anzahl. Einzelne Einträge: Wischen oder Kontextmenü «Endgültig löschen».

## Funktionale Anforderungen (Version 1)

### Navigation und Aufbau

- **Mac:** drei Spalten (Ordner | Liste | Inhalt). In der Seitenleiste stehen Inbox, Ordnerbaum, Tags und «Zuletzt gelöscht».
- **iPhone:** dieselbe Hierarchie zum Durchtippen. Die App startet direkt in der Inbox. Der Knopf **Neue Notiz** (Stift oben rechts, am Mac auch ⌘N) legt die Notiz im gerade offenen Ordner an, also standardmässig in der Inbox.
- **Notizliste:** sortiert nach «zuletzt geändert». Angepinnte Notizen stehen oben. Jede Zeile zeigt Titel, Vorschau und Datum.

### Ordner

- anlegen, umbenennen, löschen, verschachteln
- **Unterordner:** im geöffneten Ordner oben «Neuer Unterordner» (Ordner-Symbol mit +), am Mac auch per Rechtsklick auf den Ordner. Unterordner stehen zuoberst in der Liste des Ordners. Auf dem iPhone zeigt die Seitenleiste nur die obersten Ordner (ein Tipp auf einen Ordner mit Unterordnern würde sonst nur auf- und zuklappen), am Mac den aufklappbaren Baum. In der Inbox gibt es keine Unterordner.
- **Verschieben:** am Mac per Drag'n'Drop (Notizen und Ordner auf einen Ordner oder die Inbox in der Seitenleiste). Überall auch per Kontextmenü «Verschieben nach …» mit Ordnerauswahl, auf dem iPhone zusätzlich per Wischen nach rechts. Ein Ordner kann nicht in sich selbst verschoben werden. Ist der Name am Ziel belegt, gibt es eine Nummer.
- Drag'n'Drop verwendet einen eigenen Datentyp (`ch.hebera.hirni.item`), keine Datei-URL. So kann man eine Notiz nicht aus Versehen auf den Schreibtisch und damit aus iCloud herausziehen.

### Notizen und Editor

- **Grundfunktionen:** anlegen, umbenennen, löschen, anpinnen, duplizieren («Titel Kopie», nicht angepinnt)
- **Markdown-Hervorhebung:** Die Syntax bleibt sichtbar, aber grau. Überschriften (1–6), fett, kursiv, durchgestrichen, Listen, Checklisten, Zitate, Inline-Code, Codeblöcke, Links und Tags werden gestaltet. Gerade Anführungszeichen und Bindestriche bleiben erhalten (keine automatische Ersetzung).
- **iPhone:** Formatierungsleiste über der Tastatur: Überschrift, fett, kursiv, Liste, Checkliste, Tag, Anhang (Foto, Kamera, Datei, Datenbank-Ansicht), Tastatur ausblenden.
- **Mac:** Knöpfe in der Fensterleiste mit Tastenkürzeln: Überschrift ⇧⌘H, fett ⌘B, kursiv ⌘I, Liste ⇧⌘8, Checkliste ⇧⌘L
- **Überschrift-Knopf:** wechselt reihum keine → `#` → `##` → `###` → keine
- **Listen:** Liste und Checkliste lassen sich auch auf einer leeren Zeile beginnen. Return setzt sie fort, Return in einem leeren Punkt beendet sie.
- **Checklisten:** ein Tipp bzw. Klick auf `[ ]` hakt ab, erledigte Punkte erscheinen durchgestrichen. Das `- ` davor steht in der Datei (Markdown), wird im Editor aber ausgeblendet.
- **Tabellen:** gewöhnliche Markdown-Tabellen (`| A | B |`, Trennzeile `|---|`, erste Zeile = Kopf). Der Editor zeigt sie als Raster: Zellen direkt bearbeiten, Kopf fett. Über jeder Spalte und vor jeder Zeile ein Menü «…» (einfügen, verschieben, löschen). Griff rechts: ziehen fügt Spalten an, Griff unten: ziehen fügt Zeilen an; zurückziehen entfernt leere Spalten/Zeilen am Ende wieder; antippen fügt eine an. Einfügen: iPhone Büroklammer → «Tabelle», Mac Tabellen-Knopf (⌥⌘T); neue Tabelle mit 3 Spalten und 2 Zeilen, mit Leerzeile davor und danach. In der Datei bleibt `|` in Zellen als `\|`, ein Zeilenumbruch als `<br>`.
- **Links:** `[Text](Adresse)` und eingetippte oder eingefügte Adressen (`https://…`, `http://…`, `www.…`) erscheinen blau unterstrichen. Ein Tipp (iPhone) bzw. Klick (Mac) öffnet sie im Browser. Satzzeichen am Ende gehören nicht zur Adresse, `_` und `#` in Adressen formatieren nichts.
- **Tags:** Nach `#` erscheinen passende Tags aus dem ganzen hirni-Ordner (die häufigsten zuerst) und aus der offenen Notiz, auch eben erst getippte. Auf dem iPhone in der Leiste, am Mac unter dem Text, dort übernimmt Tab den ersten Vorschlag. Tags dürfen Buchstaben (auch Umlaute), Ziffern, `_`, `-` und `/` enthalten, aber nicht nur aus Ziffern bestehen (wie bei Obsidian).
- **Bilder und PDFs einfügen:** iPhone über die Büroklammer in der Leiste (Foto-Mediathek, bis 10 Fotos auf einmal, Kamera, Datei). Mac über die Büroklammer in der Fensterleiste (⇧⌘A) oder per Drag'n'Drop einer Datei in den Text. Fotos werden als JPEG mit höchstens 3000 Pixeln gespeichert. Standortdaten und andere Metadaten werden dabei entfernt. HEIC-Dateien werden in JPEG umgewandelt.
- **Anzeige:** Bilder und die erste PDF-Seite erscheinen direkt unter ihrer Zeile (Bilder höchstens 360 Punkte hoch, PDFs 260). Der Verweis selbst bleibt klein und grau sichtbar. Fehlt die Datei, erscheint ein Hinweis-Symbol. Antippen bzw. Klicken öffnet die Vorschau (QuickLook).
- **Notizliste:** Anhänge erscheinen in der Vorschau als `[Bild]` bzw. `[PDF]`.
- **Noch nicht:** Bild einfügen per Einsetzen (⌘V) und Drag'n'Drop auf dem iPhone.
- **Speichern:** automatisch, ohne Speichern-Knopf

### Vorlagen

- **Ordner «Vorlagen»:** wird beim Start angelegt und erscheint wie jeder Ordner in der Seitenleiste. Jede Notiz darin ist eine Vorlage. Vorlagen werden wie Notizen angelegt, bearbeitet, umbenannt und gelöscht. Tags in Vorlagen zählen in der Tag-Liste nicht.
- **Neue Notiz:** Gibt es Vorlagen (und ist nicht gerade der Ordner «Vorlagen» gewählt), fragt «Neue Notiz» nach: «Leere Notiz» oder eine Vorlage. Die Notiz heisst wie die Vorlage.
- **Neue Zeilen-Seite:** «Seite anlegen» fragt ebenso nach: «Leere Seite» oder eine Vorlage. Die Seite heisst wie der Eintrag.
- **Platzhalter** (im Text und im Namen der Vorlage, Gross/klein egal; unbekannte bleiben stehen):
  - **Datum und Zeit:** `{{datum}}` 30.10.2026, `{{iso-datum}}` 2026-10-30, `{{zeit}}` 14:30, `{{wochentag}}` Freitag, `{{kw}}` 44 (ISO-Kalenderwoche), `{{monat}}` Oktober, `{{quartal}}` Q4, `{{jahr}}` 2026.
  - **Relative Daten:** `{{morgen}}`, `{{übermorgen}}`, `{{gestern}}`, `{{datum+7}}`, `{{datum-1}}`, `{{datum+2w}}` (Wochen), `{{datum+1m}}` (Monate), `{{iso-datum+7}}`, `{{nächster montag}}` bzw. `{{montag}}` (nächster solcher Tag nach heute).
  - `{{titel}}`: Titel der neuen Notiz. Auf Zeilen-Seiten zusätzlich `{{Feldname}}` mit dem Wert des Eintrags; ein gleichnamiges Feld (z. B. «Datum») geht vor.
  - **Rückfragen:** `{{frage: Mit wem?}}` (Textfeld) und `{{wahl: Arbeit|Privat|Verein}}` (Auswahl, erste vorbelegt). Beim Anlegen erscheint ein Blatt «Neue Notiz» mit allen Fragen; gleiche Fragen nur einmal, die Antwort steht überall (auch im Titel). Auf Zeilen-Seiten wird nicht gefragt, die Platzhalter bleiben dort leer.
  - `{{cursor}}`: Dort steht nach dem Anlegen der Cursor (Tastatur offen).
  - **Beispieltext** `{{? Thema der Besprechung}}`: bleibt in der Notiz, bis man ihn überschreibt. Der Editor zeigt nur «Thema der Besprechung», grau und kursiv; ein Tipp darauf markiert ihn ganz, Tippen ersetzt ihn. Ohne `{{cursor}}` ist nach dem Anlegen der erste Beispieltext markiert. In Vorschau und PDF erscheint er nicht.
  - `- [ ] Nachfassen {{stichtag: +7}}`: Der Platzhalter verschwindet aus der Zeile, die Pendenz bekommt den Stichtag (gleiche Angaben wie bei den relativen Daten, auch `03.11.2026`).
  - `{{nr}}`: laufende Nummer pro Vorlage (1, 2, 3 …). `{{vorherige}}`: Link auf die zuletzt aus dieser Vorlage angelegte Notiz («–» beim ersten Mal). Beides gemerkt in `_Hirni/Vorlagen.json`.
  - `{{pendenzen}}` bzw. `{{pendenzen #büro}}`: offene Pendenzen (alle bzw. einer Kategorie) als Liste mit Link zur Notiz, ohne Checkbox (damit keine doppelten Pendenzen entstehen).
  - `{{termine heute}}` bzw. `{{termine morgen}}`: Einträge aus Datenbanken mit eingeschaltetem Apple Kalender an diesem Tag, mit Uhrzeit und Link.
  - Links `hirni://…` öffnen die Notiz in Hirni.
- `angepinnt` und `hirni-zeile` aus dem Kopf der Vorlage werden nicht übernommen, andere Kopfzeilen schon.

### Teilen und Export

- **Menü «Teilen»** im Editor (iPhone oben rechts, Mac in der Fensterleiste): «Als PDF teilen», «Als Markdown teilen», am Mac zusätzlich «Als PDF exportieren …» (⇧⌘E, Sichern-Dialog). Vorher werden ungespeicherte Eingaben gesichert.
- **PDF:** A4, Ränder 16 mm, Systemschrift. Ohne Markdown-Zeichen: Überschriften, Absätze, Listen, Checklisten (☐/☑ mit Erledigt-Datum), Zitate, Codeblöcke, Tabellen, Bilder (auf eigener Zeile; PDFs und fehlende Bilder als Hinweis), Links, Tags. Eingebettete Datenbanken erscheinen als Tabelle ihrer Ansicht (sichtbare Felder, Filter, Sortierung, Gruppen, Berechnungen); Kalender und Diagramm ebenfalls als Tabelle ihrer Einträge. Der Titel steht oben, ausser die Notiz beginnt schon mit ihm als Überschrift.
- **Technik:** Hirni erzeugt HTML (`NoteHTML`) und lässt WebKit es auf Seiten verteilen (iPhone: Druck-Renderer, Mac: Druckauftrag in eine Datei).

### Teilen in Hirni

- **Hirni im Teilen-Menü** anderer Apps (iPhone und Mac): Links, Texte, Bilder (bis 10) und PDFs. Ein Blatt «In Hirni sichern» zeigt Titel (änderbar), Text und Anhänge; «Sichern» legt eine Notiz in der **Inbox** an.
- **Notiz:** zuerst der Text bzw. Link, darunter die Anhänge je auf eigener Zeile (Dateien in `Inbox/_Anhänge/`). Titel: Seitentitel, sonst erste Textzeile (max. 60 Zeichen), sonst Domain, sonst «Geteilt».
- **Technik:** Erweiterung `HirniShare` (Bundle-ID `ch.hebera.hirni.share`) schreibt direkt in iCloud Drive. Ist iCloud nicht erreichbar, legt sie den Eintrag in die Warteschlange `Geteilt/` im gemeinsamen App-Gruppen-Ordner (`group.ch.hebera.hirni`); Hirni holt sie beim Start und beim Zurückkehren in die App ab (`SharedInbox`).

### Widget und Kurzbefehle

- **Widget «Pendenzen»** (iPhone: klein, mittel, gross, Sperrbildschirm; Mac: klein, mittel, gross): Anzahl offener Pendenzen und die nächsten, nach Kategorie gruppiert wie in der Liste (Überschrift #kategorie, alphabetisch, «Ohne Kategorie» zuletzt; darin mit Stichtag zuerst). Die Kategorie steht nur in der Überschrift, nicht nochmals im Text. Auch die Liste in der Menüleiste am Mac ist so gruppiert. Darunter Notiz und «fällig heute/morgen/Sa. 31. Okt.», überfällig rot. Der Kreis vor einer Pendenz hakt sie direkt im Widget ab, ohne Hirni zu öffnen (mit ✅ Datum in der Notiz). Antippen des Texts öffnet die Notiz, sonst die Pendenzenliste.
- **Technik Widget:** Die App legt `Widget.json` (`WidgetSnapshot`) in den gemeinsamen App-Gruppen-Ordner, sobald sich Pendenzen oder Stichtage ändern; das Widget liest es. Beim Abhaken schreibt das Widget selbst in die Notiz in iCloud Drive; ist iCloud nicht erreichbar, merkt es sich die Pendenz in `Erledigt.json` im gemeinsamen Ordner, und Hirni hakt sie beim Start bzw. beim Zurückkehren ab (`WidgetCompletions`). Gemeinsamer Ordner: iPhone `group.ch.hebera.hirni`, Mac `<Team-ID>.ch.hebera.hirni` (Einstellung `HIRNI_APP_GROUP` in Config/Signing.xcconfig; am Mac braucht «group.» eine Freigabe im Profil). Links: `hirni://pendenzen`, `hirni://notiz?pfad=Inbox/Einkauf.md`.
- **Kurzbefehle / Siri** (ohne Hirni zu öffnen): «Neue Notiz» (Text; erste Zeile = Titel, landet in der Inbox), «Neue Pendenz» (hängt `- [ ] …` an die Notiz «Pendenzen» in der Inbox an, legt sie bei Bedarf an), «Pendenzen zeigen» (öffnet Hirni). Siri-Sätze z. B. «In Hirni notieren», «Pendenz in Hirni erfassen», «Pendenzen in Hirni zeigen». Sätze mit «Notiz» meidet Hirni: Siri leitet sie an Apples Notizen-Befehl weiter und meldet, Hirni unterstütze den Vorgang nicht.

### Menüleiste am Mac

- **Hirni-Symbol in der Menüleiste** (Gehirn): Klick öffnet ein Fenster mit «Notiz | Pendenz».
  - **Notiz:** Textfeld, erste Zeile = Titel; «In Inbox sichern» (⌘↩).
  - **Pendenz:** einzeilig, Eingabetaste erfasst; landet als `- [ ] …` in der Notiz «Pendenzen» in der Inbox (wie der Kurzbefehl).
  - Darunter die nächsten 6 offenen Pendenzen (wie im Widget) mit Kreis zum Abhaken; «Hirni öffnen», «Beenden».
- Das Symbol bleibt, auch wenn das Hirni-Fenster geschlossen ist. Ein- und ausblenden in den Einstellungen (Hirni ▸ Einstellungen …, ⌘,).

### Termine im Apple Kalender

- **Pro Datenbank einschalten:** Symbol «Apple Kalender» in der Symbolleiste der Datenbank → «Im Kalender «Hirni» zeigen» (bei mehreren Datumsfeldern: welches). Gespeichert in der Datenbank-Datei als Kopfzeile `kalender: "Wann"`; gilt damit auf allen Geräten. Feld umbenannt → wird mitgenommen; gelöscht oder kein Datum mehr → aus.
- **Eigener Kalender «Hirni»** (violett), wenn möglich in iCloud, damit ihn alle Geräte sehen. Die Termine mischen sich nicht mit anderen Kalendern und lassen sich im Kalender-App mit einem Häkchen ein- und ausblenden.
- **Termin pro Eintrag:** Titel = erstes Feld (sonst Name der Datenbank); Datum ohne Uhrzeit → ganztägig (Zeiträume über mehrere Tage), mit Uhrzeit → ab dieser Zeit, 1 Stunde bzw. bis zur Endzeit. Link `hirni://notiz?pfad=…&zeile=…` öffnet die Datenbank in Hirni.
- **Nur in eine Richtung:** Hirni ist die Quelle. Hirni gleicht bei jedem Einlesen ab: neue Einträge anlegen, geänderte nachführen, gelöschte und doppelte (z. B. von beiden Geräten) entfernen. Im Kalender «Hirni» von Hand Geändertes wird überschrieben, von Hand Angelegtes entfernt.
- **Zugriff:** Hirni fragt nach vollem Kalenderzugriff erst, wenn die erste Datenbank eingeschaltet wird.
- **Technik:** `CalendarSync` (HirniKit) plant, `CalendarExporter` (App, EventKit) führt aus.

### Pendenzen

- **Quelle:** Jede Checkbox-Zeile (`- [ ] …`) in einer Notiz ist eine Pendenz. Es gibt keine eigene Pendenzen-Datei; die Notizen bleiben die einzige Quelle. Vorlagen und Codeblöcke zählen nicht, leere Checkboxen auch nicht.
- **Erledigt-Datum in der Zeile** (wie beim Obsidian-Plugin «Tasks»): Abhaken (in der Notiz oder in der Liste) setzt `[x]` und `✅ 2026-10-30`, wieder öffnen entfernt beides. Der Editor zeigt das Datum klein und grau. Ein Erfasst-Datum gibt es nicht (eine frühere Version schrieb `➕ Datum`; das wird beim ersten Start einmal entfernt).
- **Neue Pendenz ohne Notiz:** «+» in der Liste: Text, Kategorie (bestehende wählen oder neue eintippen), Stichtag. Sie wird als `- [ ] …` an die Notiz «Pendenzen» in der Inbox angehängt (wie Kurzbefehl und Menüleiste; die Notiz entsteht bei Bedarf).
- **Löschen:** in der Liste über Kontextmenü «Löschen …», iPhone auch Wischen nach links, Mac auch ⌫ bei gewählter Pendenz. Nach Rückfrage wird die ganze Zeile aus der Notiz entfernt (samt Stichtag); die Notiz selbst bleibt.
- **Stichtag:** nur in der Liste (Kontextmenü «Stichtag …», «Stichtag entfernen»), nie in der Notiz. Gespeichert in `_Hirni/Pendenzen.json` als `{"stichtage": {"<Pfad der Notiz>|<Text der Pendenz>": "2026-11-03"}}`. Ändert sich der Text der Pendenz oder wird die Notiz umbenannt/verschoben, geht der Stichtag verloren. Anzeige «fällig Sa. 31. Okt.», überfällig rot.
- **Kategorie:** der erste Tag in der Zeile (`#büro`). In der Liste per Kontextmenü «Kategorie» setzen, ändern oder entfernen (schreibt den Tag in die Zeile, vor die Daten).
- **Liste «Pendenzen»** (Seitenleiste, mit Anzahl offener): offene nach Kategorie (alphabetisch, «Ohne Kategorie» zuletzt; darin nach Stichtag, ohne Stichtag zuletzt), darunter einklappbar «Erledigte Pendenzen» (zuletzt erledigte zuerst). Jede Zeile zeigt Text, Notiz, Stichtag bzw. Erledigt-Datum. Antippen öffnet die Notiz; der Kreis hakt ab bzw. öffnet wieder (iPhone auch Wischen nach rechts).
- **Erinnerung:** Am Stichtag um 9:00 Uhr meldet sich Hirni mit einer Mitteilung (Titel = Pendenz, darunter «Heute fällig · Notiz»), auf iPhone und Mac. Nur offene Pendenzen; erledigt oder Stichtag entfernt → Mitteilung fällt weg. Die Erlaubnis fragt Hirni beim ersten Setzen eines Stichtags (oder beim Start, falls schon eine Erinnerung ansteht). Antippen zeigt die Pendenzen und öffnet die Notiz. Geplant werden die nächsten 60 (iOS erlaubt 64 pro App), bei jedem Einlesen neu. Technik: `TaskReminders` (HirniKit) plant, `ReminderScheduler` (App) übergibt sie an das System.

### Tags und Suche

- **Tags:** Die Seitenleiste zeigt unter «Tags» alle Tags mit der Anzahl Notizen, die häufigsten zuerst. Ein Tipp listet alle Notizen mit diesem Tag aus allen Ordnern, `#ferien` zeigt dabei auch `#ferien/2026`. Eine neue Notiz aus der Tag-Ansicht landet in der Inbox und hat den Tag schon drin.
- **Volltextsuche:** Suchfeld über der Notizliste (auf dem iPhone unten). Jedes Wort muss vorkommen, auch als Wortanfang («ferie» findet «Ferien»). Gross/klein und Akzente spielen keine Rolle («uber» findet «Über»). Titeltreffer stehen zuerst. Bereich: «Überall» oder «In ‹Ordner›» (samt Unterordnern). Treffer zeigen Ordner und einen Textausschnitt mit fett markierten Wörtern. Auch Einträge in Datenbanken werden gefunden.
- **Such-Index:** SQLite mit FTS5 im Cache-Ordner des Geräts (`hirni-suche.sqlite`). Er wird bei jedem Neueinlesen nachgeführt, gelesen werden nur geänderte Dateien. Fehlt er, baut ihn hirni beim nächsten Start neu auf.

### Datenbanken

- **Anlegen:** Knopf «Neue Datenbank» (Tabellen-Symbol) über der Notizliste, im gerade offenen Ordner. Eine neue Datenbank hat das Textfeld «Name».
- **Felder** (Knopf mit Reglern): hinzufügen, umbenennen (die Werte wandern mit), Typ ändern, Zahlenformat, Datum mit Uhrzeit, Optionen für Auswahl/Mehrfachauswahl pflegen («Option hinzufügen» legt eine leere Option an, der Cursor steht gleich darin; Optionen lassen sich direkt umbenennen, die Einträge und Filter wandern mit; leer gelassene neue Optionen fallen weg), löschen. Übernommen wird mit «Fertig». Gingen dabei Werte verloren (gelöschtes Feld, Wert passt nicht zum neuen Typ oder zu den Optionen), fragt hirni vorher nach und nennt die Anzahl.
- **Einträge:** anlegen (+, am Mac ⇧⌘N), bearbeiten, löschen. Am Mac direkt in der Tabelle (eine Spalte pro Feld, löschen mit ⌫ oder Rechtsklick). Auf dem iPhone als Tabelle (siehe unten), ein Tipp öffnet das Formular, gelöscht wird dort mit «Eintrag löschen».
- **Tabelle am Mac:** Ist sie schmaler als das Fenster, steht sie links oben.
- **Tabelle auf dem iPhone** (und eingebettet in Notizen): alle sichtbaren Spalten nebeneinander, waagrecht und senkrecht scrollbar, mit Gruppen und Berechnungen. Die Zellen lassen sich direkt bearbeiten. Vorne die Zeilennummer: Antippen öffnet das Formular, lange drücken (Mac: gedrückt halten) zeigt «Formular öffnen», «Seite anlegen/öffnen» und «Eintrag löschen».
- **Spalten verschieben:** am Mac eine Spaltenüberschrift per Drag'n'Drop auf eine andere ziehen (die Spalte landet davor) oder rechts neben die letzte (ans Ende). Auf beiden Geräten auch unter «Felder» → «Reihenfolge» (iPhone: lange drücken und ziehen). Auch in eingebetteten Tabellen in Notizen lassen sich die Überschriften ziehen (iPhone: lange drücken). Die Reihenfolge gilt für Tabelle, Liste und Formular und steht so in der Datei. Das erste Feld ist der Titel eines Eintrags.
- **Eingaben je Typ:** Text, Zahl (formatiert, z. B. «CHF 42.50»), Auswahl-Menü, Mehrfachauswahl mit Häkchen, Datum mit Kalender (optional Zeitraum), Schalter für Checkbox, URL mit Knopf zum Öffnen.
- **Ansichten:** Leiste unter dem Titel. Antippen wechselt, + legt eine neue an, lange drücken bzw. Rechtsklick benennt um, dupliziert oder löscht. Solange es keine gespeicherte Ansicht gibt, heisst die Standardansicht «Alle». Sie wird gespeichert, sobald man etwas daran ändert. Welche Ansicht gewählt ist, merkt sich jedes Gerät nur für sich, das steht nicht in der Datei.
- **Pro Ansicht:**
  - **Filter:** mehrere Bedingungen, die alle zutreffen müssen. Die Bedingungen passen zum Feldtyp, der Wert wird je nach Typ als Auswahl, Datum oder Zahl eingegeben.
  - **Sortieren:** mehrere Felder nacheinander, auf- oder absteigend. Leere Werte stehen immer am Ende. Bei Auswahl-Feldern gilt die Reihenfolge der Optionen.
  - **Gruppieren:** nach einem Feld. Auswahl in der Reihenfolge der Optionen. Bei Mehrfachauswahl erscheint ein Eintrag in jeder seiner Gruppen. Checkbox: angehakt und nicht angehakt. Datum nach Monat.
  - **Felder ausblenden.**
  - **Berechnen:** pro Feld Anzahl, bei Zahlen auch Summe, Durchschnitt, Minimum und Maximum. Am Mac erscheinen die Ergebnisse unter den Spalten, auf dem iPhone unten in der Liste. Berechnet wird über alle sichtbaren Einträge.
- **Kalender-Ansicht** (neue Ansicht über + → Kalender):
  - **Darstellung:** Monatskalender, Woche ab Montag, Samstag und Sonntag hinterlegt, heute markiert. Blättern mit ‹ › (am Mac ⌘← und ⌘→), «Heute» springt zurück.
  - **Einträge:** stehen am Tag ihres Datumsfelds, ein Zeitraum an jedem seiner Tage. Filter der Ansicht gelten auch hier.
  - **Farben:** nach einem Auswahl- oder Mehrfachauswahlfeld («Farbe nach»), in der Reihenfolge der Optionen. Ein Farbschlüssel steht unter dem Kalender.
  - **Tag antippen:** zeigt die Einträge dieses Tages. «Neuer Eintrag an diesem Tag» setzt das Datum vor und öffnet das Formular.
  - **Felder:** Eine neue Kalender-Ansicht nimmt das erste Datumsfeld und das erste Auswahlfeld. Ohne Datumsfeld erscheint ein Hinweis.
- **Neuer Eintrag in einer gefilterten Ansicht:** bleibt sichtbar, bis man die Ansicht wechselt. Werte aus einfachen Filtern werden vorausgefüllt (z. B. «Kategorie ist Essen»).
- **Suche:** findet auch Einträge in Datenbanken. Der Treffer zeigt den Eintrag und öffnet die Datenbank.
- **Gleichzeitige Änderungen** (anderes Gerät, Claude): werden Zelle für Zelle zusammengeführt. Haben beide Seiten dieselbe Zelle verschieden geändert, bleibt die Eingabe in der App, und ein Hinweis nennt die Anzahl.
- Ansichten anlegen, umbenennen und wechseln, Filter, Sortierung und Gruppierung einstellen
- Tabelle, Kalender und Diagramm wie im Datenmodell beschrieben
- Zeilen-Seite öffnen bzw. anlegen: im Formular «Seite anlegen»/«Seite öffnen», am Mac auch im Kontextmenü einer Zeile, auf dem iPhone mit Wischen nach rechts. Zeilen mit Seite tragen ein Dokument-Symbol, am Mac öffnet ein Klick darauf die Seite. Die Seite öffnet sich innerhalb der Datenbank, «‹» führt zurück.
- Ansicht in eine Notiz einbetten, interaktiv angezeigt mitten im Text:
  - **Einfügen:** am Mac mit dem Tabellen-Knopf in der Fensterleiste (⇧⌘D), auf dem iPhone über die Büroklammer → «Datenbank-Ansicht». Eine Liste zeigt alle Datenbanken mit ihren Ansichten. Oben lässt sich direkt eine neue Datenbank anlegen (im Ordner der Notiz, zuerst nur mit dem Feld «Name»), die gleich eingebettet wird.
  - **Anzeige:** Der Block bleibt klein und grau sichtbar, darunter erscheint ein Kasten mit Name, Ansichten-Leiste und Optionen (Filter, Sortierung, Gruppierung, Felder ein-/ausblenden, Berechnungen) wie in der Datenbank. Wird die Ansicht im Kasten gewechselt, angelegt oder umbenannt, passt sich die Zeile `ansicht:` an. Tabelle: die ersten 20 Einträge mit allen sichtbaren Spalten, mit Gruppen, waagrecht scrollbar, Zellen direkt bearbeitbar, unten die Berechnungen, bei mehr ein Link «… weitere». Kalender und Diagramm wie in der Datenbank, mit Blättern und Tagesblatt.
  - **Bearbeiten:** Ein Eintrag öffnet das Formular und wird direkt in der Datenbank gespeichert. Oben rechts im Kasten: «+» (neuer Eintrag), «Felder» (Felder-Editor) und «Öffnen» (ganze Datenbank).
  - Fehlt die Datenbank, steht im Kasten ein Hinweis. Änderungen anderswo (Datenbank selbst, Claude, anderes Gerät) erscheinen sofort.
- **Zahlenfelder:** Während der Eingabe steht die blanke Zahl im Feld (`64.3`), formatiert (`CHF 64.30`) wird beim Verlassen.

### Sync und Konflikte

- hirni überwacht den iCloud-Ordner und zeigt Änderungen von anderen Geräten oder von Claude automatisch an.
- Dateien, die auf dem iPhone noch nicht heruntergeladen sind, lädt hirni beim Öffnen nach und zeigt dabei einen Fortschritt.
- **Gleichzeitig geändert, während du tippst** (Claude, Finder, anderes Gerät): Vor jedem Speichern prüft der Editor, ob die Datei inzwischen anderswo geändert wurde. Betreffen die Änderungen verschiedene Zeilen, werden beide automatisch zusammengeführt (3-Wege-Vergleich, zeilenweise). Betreffen sie dieselbe Stelle, wird nicht gespeichert, und oben erscheint ein Hinweis mit «Meine behalten», «Andere übernehmen» und «Beide behalten». Bei «Beide behalten» wird die eigene Fassung zu einer eigenen Notiz «Titel (Gerätename)».
- **iCloud-Konflikt** (dieselbe Datei auf zwei Geräten offline geändert): In der Notizliste erscheint ein oranges Warnzeichen, im Editor der Hinweis «Von dieser Notiz gibt es mehrere Fassungen». «Ansehen» zeigt alle Fassungen mit Gerät und Zeit, mit der Wahl «Diese behalten», «Diese übernehmen» oder «Alle behalten» (die anderen werden zu eigenen Notizen).
- **Unlesbare Dateien** (kein UTF-8-Text): Der Editor zeigt einen Hinweis und verändert die Datei nicht.
- **Download-Fortschritt:** Eine Notiz, die noch aus iCloud geladen wird, zeigt den Fortschritt in Prozent. In der Seitenleiste steht, wie viele Dateien iCloud gerade lädt.
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
