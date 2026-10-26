import Foundation
import Testing
@testable import HirniKit

struct TemplateTests {
    let date = ISO8601DateFormatter().date(from: "2026-10-26T13:30:00Z")! // Montag, 14:30 in Zürich

    @Test func fillsPlaceholders() {
        let text = TemplateFiller.fill("{{Wochentag}}, {{datum}} {{zeit}} – {{titel}} ({{iso-datum}}) {{Betrag}} {{unbekannt}}",
                                       title: "Treffen", date: date, values: ["Betrag": "CHF 42.50"])
        #expect(text == "Montag, 26.10.2026 14:30 – Treffen (2026-10-26) CHF 42.50 {{unbekannt}}")
    }

    @Test func fieldValuesWinOverBuiltIns() {
        #expect(TemplateFiller.fill("{{Datum}} / {{zeit}}", title: nil, date: date, values: ["Datum": "5. Sept. 2026"]) == "5. Sept. 2026 / 14:30")
    }

    @Test func noteFromTemplateUsesFilledName() throws {
        let test = try TestVault()
        #expect(test.exists("Vorlagen"))
        try test.write("---\nangepinnt: true\nquelle: x\n---\n## {{titel}}\n- [ ] ", to: "Vorlagen/Besprechung {{datum}}.md")
        #expect(test.vault.templates().map(\.name) == ["Besprechung {{datum}}"])

        let url = try test.vault.createNote(in: test.vault.inboxURL, fromTemplate: test.vault.templates()[0].url, now: date)
        #expect(url.lastPathComponent == "Besprechung 26.10.2026.md")
        #expect(try test.vault.readNote(at: url) == "---\nquelle: x\n---\n## Besprechung 26.10.2026\n- [ ] ")
    }

    @Test func rowPageFromTemplate() throws {
        let test = try TestVault()
        try test.write("Ausgabe {{titel}}: {{Betrag CHF}}", to: "Vorlagen/Ausgabe.md")
        let db = try test.vault.createDatabase(in: test.vault.inboxURL, title: "Ausgaben")
        let page = try test.vault.rowPage(for: db, rowID: "r1", title: "Pizza",
                                          template: test.vault.templates()[0].url, values: ["Betrag CHF": "CHF 42.50"], now: date)
        #expect(try test.vault.readNote(at: page) == "---\nhirni-zeile: r1\n---\nAusgabe Pizza: CHF 42.50")
    }

    @Test func templateTagsAreNotCounted() throws {
        let test = try TestVault()
        try test.write("#vorlage", to: "Vorlagen/A.md")
        try test.write("#echt", to: "Inbox/B.md")
        #expect(test.vault.allTags().map(\.name) == ["echt"])
    }
}
