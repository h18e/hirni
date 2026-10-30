/// Inhalt der Hilfe. Bei neuen Funktionen hier nachführen (wie docs/spec.md).
extension HelpTopic {
    static let all: [HelpTopic] = [
        basics, notes, templates, placeholders, tasks, databases,
        search, sharing, quickCapture, calendar, sync, troubleshooting,
    ]

    static let basics = HelpTopic(
        id: "grundlagen", title: "Erste Schritte", systemImage: "brain.head.profile",
        summary: "Wie Hirni aufgebaut ist und wo deine Notizen liegen.",
        sections: [
            .init(title: "Aufbau", items: [
                "**Seitenleiste:** Inbox, Pendenzen, Ordner, Tags, Hilfe und «Zuletzt gelöscht».",
                "**Mac:** drei Spalten – Seitenleiste | Liste | Inhalt. **iPhone:** dieselben Ebenen zum Durchtippen, Hirni startet in der Inbox.",
                "**Inbox:** Sammelort für alles Neue, auch für Geteiltes, Kurzbefehle und die Menüleiste.",
                "Die Notizliste ist nach «zuletzt geändert» sortiert, angepinnte Notizen stehen oben.",
            ]),
            .init(title: "Ordner und Unterordner", items: [
                "**Neuer Ordner:** Ordner-Symbol mit + oben in der Seitenleiste.",
                "**Neuer Unterordner:** im geöffneten Ordner oben das Ordner-Symbol mit +; am Mac auch Rechtsklick auf den Ordner. In der Inbox gibt es keine Unterordner.",
                "Unterordner stehen zuoberst in der Liste ihres Ordners. Am Mac zeigt die Seitenleiste den ganzen Baum zum Aufklappen.",
                "**Verschieben:** Kontextmenü «Verschieben nach …», iPhone auch nach rechts wischen, Mac auch Drag'n'Drop auf einen Ordner.",
                "Umbenennen und Löschen: Kontextmenü auf dem Ordner (lange drücken bzw. Rechtsklick).",
            ]),
            .init(title: "Wo die Daten liegen", items: [
                "Alles liegt in **iCloud Drive → Hirni** als gewöhnliche Dateien: Notizen als Markdown (`.md`), Datenbanken als `.hirnidb.md`, Bilder im Ordner `_Anhänge`.",
                "Du kannst die Dateien auch im Finder, in der Dateien-App, mit Obsidian oder Claude lesen und bearbeiten. Hirni zeigt Änderungen von dort automatisch an.",
                "Hirni speichert automatisch, es gibt keinen Speichern-Knopf.",
            ]),
        ]
    )

    static let notes = HelpTopic(
        id: "notizen", title: "Notizen und Editor", systemImage: "square.and.pencil",
        summary: "Schreiben, formatieren, Listen, Tabellen, Bilder und Links.",
        sections: [
            .init(title: "Notizen", items: [
                "**Neue Notiz:** Stift oben rechts (Mac ⌘N). Gibt es Vorlagen, wählst du «Leere Notiz» oder eine Vorlage.",
                "Anpinnen, Duplizieren, Verschieben und Löschen über das Kontextmenü in der Liste.",
                "Gelöschte Notizen landen in «Zuletzt gelöscht» und lassen sich dort wiederherstellen.",
            ]),
            .init(title: "Formatieren", items: [
                "Hirni schreibt Markdown: Die Zeichen bleiben sichtbar, aber grau.",
                "`# Titel`, `## Untertitel` – **fett** mit `**…**`, *kursiv* mit `*…*`, durchgestrichen mit `~~…~~`.",
                "**iPhone:** Leiste über der Tastatur (Überschrift, fett, kursiv, Liste, Checkliste, Tag, Büroklammer).",
                "**Mac:** Überschrift ⇧⌘H (wechselt # → ## → ### → keine), fett ⌘B, kursiv ⌘I, Liste ⇧⌘8, Checkliste ⇧⌘L.",
                "Listen und Checklisten setzt Return fort; Return in einem leeren Punkt beendet die Liste.",
            ]),
            .init(title: "Checklisten", items: [
                "`- [ ] Text` ist eine Checkbox; ein Tipp auf `[ ]` hakt ab und schreibt das Datum dazu (`✅ 2026-10-30`).",
                "Jede Checkbox erscheint automatisch in der Liste **Pendenzen**.",
            ]),
            .init(title: "Tags und Links", items: [
                "`#tag` irgendwo im Text. Nach `#` schlägt Hirni bekannte Tags vor (Mac: Tab übernimmt den ersten).",
                "Unter-Tags mit `/`: `#ferien/2026` erscheint auch unter `#ferien`.",
                "Adressen (`https://…`, `www.…`) und `[Text](Adresse)` werden zu Links; ein Tipp öffnet sie. `hirni://…`-Links öffnen eine Notiz in Hirni.",
            ]),
            .init(title: "Tabellen", items: [
                "**Einfügen:** iPhone Büroklammer → «Tabelle», Mac Tabellen-Knopf (⌥⌘T).",
                "Zellen direkt bearbeiten. Menü «…» über jeder Spalte und vor jeder Zeile: einfügen, verschieben, löschen.",
                "Griff rechts bzw. unten ziehen fügt Spalten bzw. Zeilen an; zurückziehen entfernt leere wieder.",
            ]),
            .init(title: "Bilder und PDFs", items: [
                "iPhone: Büroklammer → Fotos (bis 10), Kamera oder Datei. Mac: Büroklammer (⇧⌘A) oder Datei in den Text ziehen.",
                "Fotos werden verkleinert (max. 3000 Pixel) und ohne Standortdaten gespeichert.",
                "Antippen öffnet die Vorschau.",
            ]),
            .init(title: "Datenbank in einer Notiz", items: [
                "Mac ⇧⌘D bzw. iPhone Büroklammer → «Datenbank-Ansicht»: eine Ansicht einer Datenbank direkt im Text, voll bearbeitbar.",
                "Oben in der Auswahl lässt sich auch gleich eine neue Datenbank anlegen.",
            ]),
        ]
    )

    static let templates = HelpTopic(
        id: "vorlagen", title: "Vorlagen", systemImage: "doc.on.doc",
        summary: "Wiederkehrende Notizen mit einem Tipp anlegen.",
        sections: [
            .init(title: "So funktioniert's", items: [
                "Jede Notiz im Ordner **Vorlagen** ist eine Vorlage. Du bearbeitest sie wie jede Notiz.",
                "**Neue Notiz aus Vorlage:** Stift → Vorlage wählen. Die neue Notiz heisst wie die Vorlage.",
                "**Zeilen-Seite aus Vorlage:** in einer Datenbank «Seite anlegen» → Vorlage wählen.",
                "Platzhalter wie `{{datum}}` werden beim Anlegen ausgefüllt – im Text **und im Namen** der Vorlage. Alle Platzhalter stehen im Thema **Platzhalter**.",
                "Tags in Vorlagen zählen in der Tag-Liste nicht, Checkboxen in Vorlagen nicht als Pendenzen.",
            ]),
            .init(title: "Beispiel «Besprechung»", items: [
                "Name der Vorlage: `Besprechung {{frage: Mit wem?}} {{datum}}`",
                "Text: `# {{? Thema}}` – `Mit {{frage: Mit wem?}} · {{wahl: Arbeit|Privat}}` – `Letztes Mal: {{vorherige}}` – `## Notizen` – `{{cursor}}` – `## Pendenzen` – `- [ ] Protokoll verschicken {{stichtag: morgen}}` – `{{pendenzen #büro}}`",
                "Beim Anlegen fragt Hirni «Mit wem?» und «Arbeit/Privat», füllt alles aus, setzt die Stichtage und stellt den Cursor unter «Notizen».",
            ]),
        ]
    )

    static let placeholders = HelpTopic(
        id: "platzhalter", title: "Platzhalter", systemImage: "curlybraces",
        summary: "Alle Platzhalter für Vorlagen: Datum, Fragen, Cursor, Beispieltext, Pendenzen und mehr.",
        sections: [
            .init(title: "Datum und Zeit", items: [
                "`{{datum}}` → 30.10.2026 · `{{iso-datum}}` → 2026-10-30 · `{{zeit}}` → 14:30",
                "`{{wochentag}}` → Freitag · `{{kw}}` → 44 (Kalenderwoche) · `{{monat}}` → Oktober · `{{quartal}}` → Q4 · `{{jahr}}` → 2026",
            ]),
            .init(title: "Relative Daten", items: [
                "`{{morgen}}`, `{{übermorgen}}`, `{{gestern}}`",
                "`{{datum+7}}` in 7 Tagen, `{{datum-1}}` gestern, `{{datum+2w}}` in 2 Wochen, `{{datum+1m}}` in einem Monat",
                "`{{iso-datum+7}}` dasselbe im Format 2026-11-06",
                "`{{nächster montag}}` oder `{{montag}}`: der nächste Montag nach heute (jeder Wochentag geht)",
            ]),
            .init(title: "Fragen beim Anlegen", items: [
                "`{{frage: Mit wem?}}` – Hirni fragt beim Anlegen in einem Textfeld nach.",
                "`{{wahl: Arbeit|Privat|Verein}}` – Auswahl, die erste ist vorgewählt.",
                "Kommt dieselbe Frage mehrmals vor (auch im Namen), fragt Hirni nur einmal und setzt die Antwort überall ein.",
                "Bei Zeilen-Seiten fragt Hirni nicht; dort bleiben diese Platzhalter leer.",
            ]),
            .init(title: "Cursor und Beispieltext", items: [
                "`{{cursor}}` – hier steht nach dem Anlegen der Cursor, die Tastatur ist offen.",
                "`{{? Thema der Besprechung}}` – Beispieltext: erscheint grau und kursiv. Ein Tipp darauf markiert ihn ganz, was du tippst, ersetzt ihn. Gibt es kein `{{cursor}}`, ist der erste Beispieltext gleich markiert.",
                "Nicht überschriebene Beispieltexte erscheinen weder in der Vorschau der Liste noch im PDF.",
            ]),
            .init(title: "Pendenzen und Nummern", items: [
                "`- [ ] Nachfassen {{stichtag: +7}}` – die Pendenz bekommt einen Stichtag (wie bei den relativen Daten: `morgen`, `+7`, `+2w`, `montag`, `03.11.2026` …). Der Platzhalter verschwindet aus der Zeile.",
                "`{{nr}}` – laufende Nummer pro Vorlage: 1, 2, 3 …",
                "`{{vorherige}}` – Link auf die letzte Notiz aus derselben Vorlage (beim ersten Mal «–»).",
                "`{{pendenzen}}` – alle offenen Pendenzen als Liste mit Link zur Notiz; `{{pendenzen #büro}}` nur eine Kategorie. Ohne Checkbox, damit keine doppelten Pendenzen entstehen.",
                "`{{termine heute}}` bzw. `{{termine morgen}}` – Einträge aus Datenbanken, die im Apple Kalender erscheinen.",
            ]),
            .init(title: "Sonst noch", items: [
                "`{{titel}}` – Titel der neuen Notiz.",
                "Auf Zeilen-Seiten: `{{Feldname}}` mit dem Wert des Eintrags, z. B. `{{Betrag}}`.",
                "Gross-/Kleinschreibung spielt keine Rolle. Unbekannte Platzhalter bleiben einfach stehen.",
            ]),
        ]
    )

    static let tasks = HelpTopic(
        id: "pendenzen", title: "Pendenzen", systemImage: "checklist",
        summary: "Alle Checkboxen aus allen Notizen an einem Ort, mit Kategorie, Stichtag und Erinnerung.",
        sections: [
            .init(title: "Die Liste", items: [
                "Jede `- [ ]`-Zeile in einer Notiz ist eine Pendenz. Die Liste **Pendenzen** in der Seitenleiste sammelt alle.",
                "Gruppiert nach **Kategorie** (erster `#tag` in der Zeile), darin nach Stichtag. Darunter die erledigten.",
                "Kreis antippen hakt ab (iPhone auch nach rechts wischen); Zeile antippen öffnet die Notiz.",
            ]),
            .init(title: "Neue Pendenz ohne Notiz", items: [
                "**+** oben in der Liste (Mac ⌘N): Text, Kategorie und auf Wunsch Stichtag.",
                "Sie landet in der Notiz **Pendenzen** in der Inbox (Hirni legt sie bei Bedarf an).",
            ]),
            .init(title: "Bearbeiten", items: [
                "Kontextmenü (lange drücken bzw. Rechtsklick): Erledigt, Notiz öffnen, Stichtag, Kategorie, Löschen.",
                "**Stichtag** steht nur in der Liste, nicht in der Notiz. Überfällige erscheinen rot.",
                "**Löschen:** iPhone nach links wischen, Mac ⌫ – entfernt die Zeile aus der Notiz (nach Rückfrage).",
            ]),
            .init(title: "Erinnerung", items: [
                "Am Stichtag um **9:00 Uhr** kommt eine Mitteilung, auf iPhone und Mac. Antippen öffnet die Notiz.",
                "Hirni fragt beim ersten Stichtag nach der Erlaubnis. Falls verpasst: Einstellungen → Mitteilungen → Hirni.",
            ]),
        ]
    )

    static let databases = HelpTopic(
        id: "datenbanken", title: "Datenbanken", systemImage: "tablecells",
        summary: "Tabellen mit Feldern, Ansichten, Filtern, Kalender und Diagramm.",
        sections: [
            .init(title: "Anlegen und Felder", items: [
                "**Neue Datenbank:** Tabellen-Symbol über der Notizliste.",
                "**Felder** (Regler-Knopf): Text, Zahl (mit Format wie CHF), Auswahl, Mehrfachauswahl, Datum (auch Zeitraum, mit Uhrzeit), Checkbox, URL.",
                "Das **erste Feld** ist der Titel eines Eintrags. Reihenfolge: Spaltenkopf ziehen oder unter Felder → Reihenfolge.",
            ]),
            .init(title: "Einträge", items: [
                "**+** (Mac ⇧⌘N) legt einen Eintrag an. Zellen direkt bearbeiten oder das Formular öffnen.",
                "**Seite anlegen:** Jeder Eintrag kann eine eigene Notiz bekommen (auch aus einer Vorlage).",
            ]),
            .init(title: "Ansichten", items: [
                "Leiste unter dem Titel: Tabelle, Liste, **Kalender** und **Diagramm**; + legt eine neue an.",
                "Pro Ansicht: Filter, Sortieren, Gruppieren, Felder ausblenden, Berechnen (Summe, Durchschnitt …).",
                "Kalender: blättern mit ‹ › (Mac ⌘← ⌘→), Tag antippen zeigt seine Einträge.",
            ]),
            .init(title: "In Notizen einbetten", items: [
                "Mac ⇧⌘D bzw. iPhone Büroklammer → «Datenbank-Ansicht». Die Ansicht erscheint mitten im Text und bleibt bearbeitbar.",
            ]),
        ]
    )

    static let search = HelpTopic(
        id: "suche", title: "Suche und Tags", systemImage: "magnifyingglass",
        summary: "Alles wiederfinden – Volltext und Tags.",
        sections: [
            .init(title: "Suche", items: [
                "Suchfeld über der Liste (iPhone unten). Jedes Wort muss vorkommen, auch als Wortanfang: «ferie» findet «Ferien».",
                "Gross/klein und Akzente egal. Bereich «Überall» oder nur der aktuelle Ordner.",
                "Findet auch Einträge in Datenbanken.",
            ]),
            .init(title: "Tags", items: [
                "Die Seitenleiste zeigt alle Tags mit Anzahl. Ein Tipp listet alle Notizen mit diesem Tag.",
                "Eine neue Notiz aus der Tag-Ansicht hat den Tag schon drin.",
            ]),
        ]
    )

    static let sharing = HelpTopic(
        id: "teilen", title: "Teilen und Export", systemImage: "square.and.arrow.up",
        summary: "Notizen als PDF oder Markdown weitergeben – und Inhalte in Hirni hineinteilen.",
        sections: [
            .init(title: "Aus Hirni teilen", items: [
                "Im Editor oben **Teilen**: «Als PDF teilen» (A4, mit Tabellen, Bildern und Datenbanken) oder «Als Markdown teilen».",
                "Mac: zusätzlich «Als PDF exportieren …» (⇧⌘E).",
            ]),
            .init(title: "In Hirni teilen", items: [
                "In Safari, Fotos, Mail usw. **Teilen → Hirni**: Links, Texte, Bilder (bis 10) und PDFs werden zu einer Notiz in der Inbox.",
                "Den Titel kannst du im Blatt noch ändern. Mac: Sichern mit der Eingabetaste.",
                "Fehlt Hirni im Teilen-Menü am Mac: Systemeinstellungen → Allgemein → Anmeldeobjekte & Erweiterungen → Teilen.",
            ]),
        ]
    )

    static let quickCapture = HelpTopic(
        id: "schnellerfassung", title: "Widget, Siri und Menüleiste", systemImage: "bolt",
        summary: "Schnell erfassen und abhaken, ohne Hirni zu öffnen.",
        sections: [
            .init(title: "Widget «Pendenzen»", items: [
                "iPhone: Home-Bildschirm lange drücken → Bearb. → Widget hinzufügen → Hirni. Mac: Rechtsklick auf den Schreibtisch → Widgets bearbeiten.",
                "Zeigt die offenen Pendenzen nach Kategorie. **Kreis** = direkt abhaken, **Text** = Notiz öffnen.",
                "Grössen: klein, mittel, gross; auf dem iPhone auch für den Sperrbildschirm.",
            ]),
            .init(title: "Siri und Kurzbefehle", items: [
                "«**In Hirni notieren**» (auch «Notiere in Hirni», «Schreib in Hirni») – neue Notiz in der Inbox.",
                "«**Pendenz in Hirni erfassen**» – neue Pendenz in der Notiz «Pendenzen».",
                "«**Pendenzen in Hirni zeigen**» – öffnet die Liste.",
                "Sätze mit dem Wort «Notiz» versteht Siri als Apples Notizen – darum «notieren».",
                "In der App **Kurzbefehle** gibt es dieselben Aktionen für eigene Abläufe.",
            ]),
            .init(title: "Menüleiste am Mac", items: [
                "Gehirn-Symbol oben rechts: **Notiz** (⌘↩ sichert) oder **Pendenz** (Eingabetaste) erfassen.",
                "Darunter die nächsten offenen Pendenzen zum Abhaken; «Hirni öffnen», «Beenden».",
                "Ein-/ausblenden: Hirni → Einstellungen … (⌘,).",
            ]),
        ]
    )

    static let calendar = HelpTopic(
        id: "kalender", title: "Apple Kalender", systemImage: "calendar",
        summary: "Termine aus Datenbanken im eigenen Kalender «Hirni».",
        sections: [
            .init(title: "Einschalten", items: [
                "In einer Datenbank mit Datumsfeld das **Kalender-Symbol** oben → «Im Kalender «Hirni» zeigen».",
                "Hirni legt einen eigenen, violetten Kalender **Hirni** an (in iCloud), getrennt von deinen anderen Terminen.",
                "In der Kalender-App lässt er sich wie jeder Kalender ein- und ausblenden.",
            ]),
            .init(title: "Gut zu wissen", items: [
                "Datum ohne Uhrzeit = ganztägig, mit Uhrzeit = 1 Stunde bzw. bis zur Endzeit. Titel = erstes Feld.",
                "**Nur in eine Richtung:** Änderungen machst du in Hirni. Im Kalender Geändertes wird überschrieben.",
                "Der Link im Termin öffnet die Datenbank in Hirni.",
            ]),
        ]
    )

    static let sync = HelpTopic(
        id: "sync", title: "iCloud und Konflikte", systemImage: "icloud",
        summary: "Was passiert, wenn mehrere Geräte gleichzeitig ändern.",
        sections: [
            .init(title: "Sync", items: [
                "Hirni überwacht den iCloud-Ordner und zeigt Änderungen anderer Geräte sofort an.",
                "Noch nicht geladene Dateien lädt Hirni beim Öffnen nach; die Seitenleiste zeigt, wie viele gerade laden.",
            ]),
            .init(title: "Konflikte", items: [
                "Ändert jemand anderes dieselbe Notiz, während du tippst, führt Hirni verschiedene Zeilen automatisch zusammen.",
                "Bei derselben Stelle erscheint ein Hinweis: «Meine behalten», «Andere übernehmen» oder «Beide behalten».",
                "Mehrere iCloud-Fassungen: oranges Warnzeichen in der Liste, «Ansehen» zeigt alle zur Wahl.",
            ]),
            .init(title: "Zuletzt gelöscht", items: [
                "Gelöschte Notizen bleiben 30 Tage. Wiederherstellen oder endgültig löschen; «Alle löschen» leert alles.",
            ]),
        ]
    )

    static let troubleshooting = HelpTopic(
        id: "probleme", title: "Wenn etwas nicht klappt", systemImage: "wrench.and.screwdriver",
        summary: "Häufige Stolpersteine und was hilft.",
        sections: [
            .init(title: "Häufige Fälle", items: [
                "**Keine Erinnerungen:** Einstellungen → Mitteilungen → Hirni → «Mitteilungen erlauben».",
                "**Siri sagt, Hirni unterstütze das nicht:** einen der Sätze aus dem Thema «Widget, Siri und Menüleiste» genau so sagen, ohne das Wort «Notiz».",
                "**Widget am Mac zeigt alten Stand:** Widget entfernen und neu hinzufügen (Rechtsklick auf den Schreibtisch → Widgets bearbeiten).",
                "**Kein Kalender «Hirni»:** in den Einstellungen → Datenschutz → Kalender Hirni vollen Zugriff geben.",
                "**Stichtag weg:** Wird der Text einer Pendenz geändert oder die Notiz umbenannt/verschoben, geht der Stichtag verloren – neu setzen.",
                "**Datei lässt sich nicht öffnen:** Ist sie keine Textdatei (UTF-8), zeigt Hirni einen Hinweis und verändert sie nicht.",
            ]),
        ]
    )
}
