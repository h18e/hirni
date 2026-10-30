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
}
