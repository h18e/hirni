import Foundation
import Testing
@testable import HirniKit

struct TemplatePlaceholderTests {
    /// Freitag, 30. Oktober 2026, 14:30.
    let now: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 14, minute: 30))!
    }()

    @Test func dateExpressions() {
        func day(_ expression: String) -> String? {
            DateExpression.resolve(expression, from: now).map { TaskLine.format($0) }
        }
        #expect(day("morgen") == "2026-10-31")
        #expect(day("+7") == "2026-11-06")
        #expect(day("-1") == "2026-10-29")
        #expect(day("+2w") == "2026-11-13")
        #expect(day("+1m") == "2026-11-30")
        #expect(day("montag") == "2026-11-02")
        #expect(day("nächster freitag") == "2026-11-06")
        #expect(day("03.11.2026") == "2026-11-03")
        #expect(day("Quatsch") == nil)
    }

    @Test func calendarPlaceholders() {
        let text = TemplateFiller.fill("KW {{kw}} · {{monat}} · {{quartal}} · {{jahr}} · {{morgen}} · {{datum+7}} · {{iso-datum-1}} · {{nächster montag}} · {{Unbekannt}}", title: nil, date: now)
        #expect(text == "KW 44 · Oktober · Q4 · 2026 · 31.10.2026 · 06.11.2026 · 2026-10-29 · 02.11.2026 · {{Unbekannt}}")
    }

    @Test func questionsAndAnswers() {
        let questions = TemplateQuestion.all(in: ["Besprechung {{frage: Mit wem?}}", "Mit {{frage: Mit wem?}} · {{wahl: Arbeit|Privat}}"])
        #expect(questions.map(\.id) == ["frage: Mit wem?", "wahl: Arbeit|Privat"])
        #expect(questions[1].options == ["Arbeit", "Privat"])
        var context = TemplateContext(date: now)
        context.answers = ["frage: Mit wem?": "Lea", "wahl: Arbeit|Privat": "Privat"]
        #expect(TemplateFiller.fill("Mit {{frage:Mit wem?}} · {{ wahl: Arbeit|Privat }} · {{? Thema}}", context: context)
            == "Mit Lea · Privat · {{? Thema}}")
    }

    @Test func hints() {
        let text = "# {{? Thema}}\nText"
        #expect(TemplateFiller.removingHints(text) == "# \nText")
        #expect(TemplateFiller.hintRange(containing: 4, in: text) == NSRange(location: 2, length: 11))
        #expect(TemplateFiller.hintRange(containing: 15, in: text) == nil)
        #expect(MarkdownSyntax.spans(in: text).contains { $0.kind == .hint && $0.range == NSRange(location: 6, length: 5) })
    }

    @Test func buildWithCursorDueNumberAndPrevious() throws {
        let test = try TestVault()
        try test.write("---\nangepinnt: true\n---\n# Jour fixe {{nr}}\nLetztes: {{vorherige}}\n{{cursor}}\n- [ ] Nachfassen {{stichtag: +7}}\n\n{{pendenzen #büro}}\n", to: "Vorlagen/Jour fixe {{datum}}.md")
        try test.write("- [ ] Offerte #büro\n- [ ] Velo #haus\n", to: "Inbox/Liste.md")
        let template = test.vault.templatesURL.appending(path: "Jour fixe {{datum}}.md")

        let first = try test.vault.createNote(in: test.vault.inboxURL, fromTemplate: template, answers: [:], now: now)
        let text = try test.vault.readNote(at: first.url)
        #expect(first.url.lastPathComponent == "Jour fixe 30.10.2026.md")
        #expect(text == "# Jour fixe 1\nLetztes: –\n\n- [ ] Nachfassen\n\n- Offerte #büro · [Liste](hirni://notiz?pfad=Inbox/Liste.md)\n")
        #expect(first.cursor == ("# Jour fixe 1\nLetztes: –\n" as NSString).length)
        let due = test.vault.dueDates().stichtage["Inbox/Jour fixe 30.10.2026.md|Nachfassen"]
        #expect(due == "2026-11-06")

        let second = try test.vault.createNote(in: test.vault.inboxURL, fromTemplate: template, answers: [:], now: now)
        let secondText = try test.vault.readNote(at: second.url)
        #expect(secondText.hasPrefix("# Jour fixe 2\nLetztes: [Jour fixe 30.10.2026](hirni://notiz?pfad=Inbox/Jour%20fixe%2030.10.2026.md)\n"))
    }

    @Test func titleMarksAndShortNames() {
        let marked = TemplateFiller.titleMarks(in: "2026-10-30 – {{cursor}}{{? KURZNOTIZ}}")
        #expect(marked.title == "2026-10-30 – KURZNOTIZ")
        #expect(marked.selection == NSRange(location: 13, length: 9))
        let cursor = TemplateFiller.titleMarks(in: "Besprechung {{cursor}}")
        #expect(cursor.title == "Besprechung")
        #expect(cursor.selection == NSRange(location: 12, length: 0))
        #expect(TemplateFiller.titleMarks(in: "Ohne").selection == nil)
        #expect(TemplateFiller.shortName("{{iso-datum}} – BESPRECHUNG – THEMA") == "BESPRECHUNG – THEMA")
        #expect(TemplateFiller.shortName("{{iso-datum}} – {{cursor}}{{? KURZNOTIZ}}") == "KURZNOTIZ")
        #expect(TemplateFiller.shortName("{{datum}}") == "Vorlage")
    }

    @Test func titlePatternInHeaderAndShortening() throws {
        let test = try TestVault()
        try test.write("Text {{frage: Wer?}}\n", to: "Vorlagen/{{iso-datum}} – {{? Thema}}.md")
        #expect(test.vault.shortenTemplateNames() == 1)
        let template = test.vault.templatesURL.appending(path: "Thema.md")
        let source = try test.vault.readNote(at: template)
        #expect(source == "---\nnotiztitel: \"{{iso-datum}} – {{? Thema}}\"\n---\nText {{frage: Wer?}}\n")
        #expect(test.vault.templateQuestions(template).map(\.id) == ["frage: Wer?"])

        let created = try test.vault.createNote(in: test.vault.inboxURL, fromTemplate: template, answers: ["frage: Wer?": "Lea"], now: now)
        #expect(created.url.lastPathComponent == "2026-10-30 – Thema.md")
        #expect(created.titleSelection == NSRange(location: 13, length: 5))
        let text = try test.vault.readNote(at: created.url)
        #expect(text == "Text Lea\n")
    }

    @Test func recognizesRenamedTemplatesFolder() throws {
        for name in ["Vorlagen", "00 Vorlagen", "00_Vorlagen", "01-vorlagen", "7.Vorlagen"] {
            #expect(VaultLayout.isTemplatesFolder(named: name))
        }
        for name in ["Alte Vorlagen", "Vorlagen alt", "10_Ferienplanung", "_Vorlagen"] {
            #expect(!VaultLayout.isTemplatesFolder(named: name))
        }

        let test = try TestVault()
        let manager = FileManager.default
        try manager.moveItem(at: test.vault.root.appending(path: "Vorlagen"), to: test.vault.root.appending(path: "00 Vorlagen"))
        try test.write("- [ ] In Vorlage #vorlage\n{{nr}}\n", to: "00 Vorlagen/Protokoll.md")
        try test.write("- [ ] Echte Pendenz\n", to: "Inbox/A.md")
        // Altes Hirni hat einen leeren «Vorlagen» daneben angelegt.
        try manager.createDirectory(at: test.vault.root.appending(path: "Vorlagen"), withIntermediateDirectories: true)

        #expect(test.vault.templatesURL.lastPathComponent == "00 Vorlagen")
        #expect(test.vault.templates().map(\.name) == ["Protokoll"])
        #expect(test.vault.allTasks().map(\.text) == ["Echte Pendenz"])
        #expect(test.vault.allTags().isEmpty)

        try VaultLayout.prepare(root: test.vault.root)
        #expect(!test.exists("Vorlagen"))

        // Nummern früherer Stände (mit Pfad als Schlüssel) gehen weiter.
        var state = TemplateState()
        state.vorlagen["Vorlagen/Protokoll.md"] = .init(nr: 4)
        try test.vault.saveTemplateState(state)
        let note = try test.vault.createNote(in: test.vault.inboxURL, fromTemplate: test.vault.templates()[0].url)
        #expect(try test.vault.readNote(at: note).contains("5"))
        #expect(test.vault.templateState().vorlagen.keys.sorted() == ["Protokoll.md"])
    }

    @Test func templatesFolderWithContentIsKeptAndCreatedWhenMissing() throws {
        let test = try TestVault()
        let manager = FileManager.default
        try test.write("Alt\n", to: "Vorlagen/Alt.md")
        try manager.createDirectory(at: test.vault.root.appending(path: "00 Vorlagen"), withIntermediateDirectories: true)
        try VaultLayout.prepare(root: test.vault.root)
        #expect(test.exists("Vorlagen/Alt.md"))

        try manager.removeItem(at: test.vault.root.appending(path: "00 Vorlagen"))
        try manager.removeItem(at: test.vault.root.appending(path: "Vorlagen"))
        try VaultLayout.prepare(root: test.vault.root)
        #expect(test.exists("Vorlagen"))
    }

    @Test func placeholdersInTableCells() throws {
        #expect(TemplateFiller.hintText(ofCell: " {{? Zutat}} ") == "Zutat")
        #expect(TemplateFiller.hintText(ofCell: "ca. {{? Menge}}") == nil)
        #expect(TemplateFiller.hintText(ofCell: "Text") == nil)
        #expect(TemplateFiller.displayCell("ca. {{? Menge}}") == "ca. Menge")

        // Eine Auswahl in einer Zelle steht mit `\\|` in der Datei.
        let source = #"| {{wahl: Ja\|Nein}} | {{frage: Wer?}} |"# + "\n|---|---|\n| {{pendenzen}} | {{cursor}} |\n"
        let questions = TemplateQuestion.all(in: [source])
        #expect(questions.first?.options == ["Ja", "Nein"])

        let test = try TestVault()
        try test.write(source, to: "Vorlagen/Tabelle.md")
        try test.write("- [ ] Eins\n- [ ] Zwei\n", to: "Inbox/Liste.md")
        let template = test.vault.templatesURL.appending(path: "Tabelle.md")
        let answers = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0.options.first ?? "Lea") })
        let created = try test.vault.createNote(in: test.vault.inboxURL, fromTemplate: template, answers: answers, now: now)
        let text = try test.vault.readNote(at: created.url)
        let table = try #require(MarkdownTable.tables(in: text).first)
        #expect(table.rows.count == 2)
        #expect(table.rows[0] == ["Ja", "Lea"])
        #expect(table.rows[1][0].contains("Eins") && table.rows[1][0].contains("\n"))
        let cursor = try #require(created.cursor)
        #expect(table.cell(at: cursor, in: text)?.row == 1)
        #expect(table.cell(at: cursor, in: text)?.column == 1)
    }

    @Test func cellLocations() throws {
        let text = "Vorher\n| A | B |\n|---|---|\n| x | y |\n| p | q |\nNachher"
        let table = try #require(MarkdownTable.tables(in: text).first)
        let ns = text as NSString
        #expect(table.cell(at: ns.range(of: "A").location, in: text)?.row == 0)
        #expect(table.cell(at: ns.range(of: "B").location, in: text)?.column == 1)
        #expect(table.cell(at: ns.range(of: "---").location, in: text) == nil)
        let q = table.cell(at: ns.range(of: "q").location, in: text)
        #expect(q?.row == 2 && q?.column == 1)
        #expect(table.cell(at: ns.range(of: "Nachher").location, in: text) == nil)
    }
}
