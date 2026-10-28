import Foundation
import Testing
@testable import HirniKit

struct NoteHTMLTests {
    @Test func blocksAndInline() {
        let md = """
        ---
        angepinnt: true
        ---
        # Ferien
        Text mit **fett**, *kursiv*, ~~weg~~ und `code` #ferien
        zweite Zeile <script>

        - Punkt
        - [ ] offen ➕ 2026-10-20
        - [x] erledigt ✅ 2026-10-27

        > Zitat
        Link [Bern](https://bern.ch) und www.sbb.ch/a_b.
        """
        let html = NoteHTML.page(title: "Test", markdown: md)
        #expect(html.contains("<h1 class=\"title\">Test</h1>"))
        #expect(html.contains("<h1>Ferien</h1>"))
        #expect(html.contains("<strong>fett</strong>") && html.contains("<em>kursiv</em>") && html.contains("<del>weg</del>"))
        #expect(html.contains("<code>code</code>") && html.contains("<span class=\"tag\">#ferien</span>"))
        #expect(html.contains("zweite Zeile &lt;script&gt;"))
        #expect(html.contains("<ul><li style=\"margin-left:0pt\">Punkt</li></ul>"))
        #expect(html.contains("☐</span><span class=\"text\">offen</span>"))
        #expect(html.contains("☑</span><span class=\"text\">erledigt</span> <span class=\"date\">✓ 2026-10-27</span>"))
        #expect(!html.contains("angepinnt") && !html.contains("➕"))
        #expect(html.contains("<blockquote>Zitat</blockquote>"))
        #expect(html.contains("<a href=\"https://bern.ch\">Bern</a>"))
        #expect(html.contains("<a href=\"https://www.sbb.ch/a_b\">www.sbb.ch/a_b</a>."))
    }

    @Test func titleNotDoubled() {
        let html = NoteHTML.page(title: "Ferien", markdown: "# Ferien\nText")
        #expect(!html.contains("class=\"title\""))
        #expect(html.contains("<h1>Ferien</h1>"))
    }

    @Test func tablesCodeAndImages() {
        let md = "| A | B |\n|---|---|\n| 1 | x\\|y |\n\n```\n**nicht fett**\n```\n![](_Anhänge/a.png)\n![](_Anhänge/fehlt.jpg)\n![](plan.pdf)"
        let html = NoteHTML.page(title: "T", markdown: md, image: { path in
            path.hasSuffix("a.png") ? NoteHTML.Image(data: Data([1, 2]), mimeType: "image/png") : nil
        })
        #expect(html.contains("<thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>x|y</td></tr></tbody>"))
        #expect(html.contains("<pre><code>**nicht fett**</code></pre>"))
        #expect(html.contains("src=\"data:image/png;base64,AQI=\""))
        #expect(html.contains("[Anhang: fehlt.jpg]") || html.contains("[PDF: fehlt.jpg]") || html.contains("fehlt.jpg"))
        #expect(html.contains("[PDF: plan.pdf]"))
    }

    @Test func embeddedDatabase() throws {
        let test = try TestVault()
        var db = Database(
            fields: [Field(name: "Name", type: .text), Field(name: "Betrag", type: .number, format: .chf), Field(name: "Bezahlt", type: .checkbox)],
            rows: [Row(id: "a", values: ["Name": "Pizza", "Betrag": "42.5", "Bezahlt": "ja"])]
        )
        var view = SavedView(name: "Alle")
        view.aggregates = ["Betrag": .sum]
        db.views = [view]
        let url = try test.vault.createDatabase(in: test.vault.inboxURL, title: "Ausgaben")
        try test.vault.writeDatabase(db, to: url)
        try test.write("Vorher\n```hirni-db\ndatenbank: Ausgaben\nansicht: Alle\n```\nNachher\n```hirni-db\ndatenbank: Fehlt\n```", to: "Inbox/Notiz.md")

        let html = try test.vault.html(ofNote: test.vault.inboxURL.appending(path: "Notiz.md"))
        #expect(html.contains("<div class=\"db-title\">Ausgaben · Alle</div>"))
        #expect(html.contains("<td>Pizza</td><td class=\"number\">CHF"))
        #expect(html.contains("<td>☑</td>"))
        #expect(html.contains("<tfoot>"))
        #expect(html.contains("<p>Nachher</p>"))
        #expect(html.contains("[Datenbank «Fehlt» nicht gefunden]"))
        #expect(!html.contains("hirni-db"))
    }
}
