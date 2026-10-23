import Foundation
import Testing
@testable import HirniKit

/// Hilfen, um Bereiche lesbar zu prüfen: welcher Text gehört zu welcher Art.
private func texts(_ kind: MarkdownSpan.Kind, in text: String) -> [String] {
    MarkdownSyntax.spans(in: text)
        .filter { $0.kind == kind }
        .map { (text as NSString).substring(with: $0.range) }
}

struct MarkdownSyntaxTests {
    @Test func headings() {
        let text = "# Titel\n## Unter\n#kein Titel"
        #expect(texts(.heading(level: 1), in: text) == ["# Titel"])
        #expect(texts(.heading(level: 2), in: text) == ["## Unter"])
        #expect(texts(.syntax, in: text) == ["# ", "## "])
        #expect(MarkdownSyntax.tags(in: text) == ["kein"])
    }

    @Test func boldItalicStrikeCode() {
        let text = "**fett** und *kursiv* und ~~weg~~ und `code *nicht kursiv*`"
        #expect(texts(.bold, in: text) == ["fett"])
        #expect(texts(.italic, in: text) == ["kursiv"])
        #expect(texts(.strikethrough, in: text) == ["weg"])
        #expect(texts(.inlineCode, in: text) == ["`code *nicht kursiv*`"])
    }

    @Test func boldIsNotAlsoItalic() {
        #expect(texts(.italic, in: "**fett**").isEmpty)
        #expect(texts(.italic, in: "dateiname_mit_strich").isEmpty)
    }

    @Test func checklists() {
        let text = "- [ ] offen\n- [x] erledigt\n- normal"
        let spans = MarkdownSyntax.spans(in: text)
        #expect(spans.contains(MarkdownSpan(.checkbox(checked: false), NSRange(location: 2, length: 3))))
        #expect(texts(.checkbox(checked: true), in: text) == ["[x]"])
        #expect(texts(.doneItem, in: text) == ["erledigt"])
        #expect(texts(.listMarker, in: text) == ["-", "-", "-"])
    }

    @Test func codeBlockHasNoInlineMarkup() {
        let text = "```\n**nicht fett** #keintag\n```\n#tag"
        #expect(texts(.bold, in: text).isEmpty)
        #expect(texts(.codeBlock, in: text).count == 3)
        #expect(MarkdownSyntax.tags(in: text) == ["tag"])
    }

    @Test func linksAndQuotes() {
        let text = "> Zitat mit [Link](https://hebera.ch)"
        #expect(texts(.quote, in: text) == [text])
        #expect(texts(.link, in: text) == ["Link"])
        #expect(texts(.syntax, in: text) == [">", "[", "](https://hebera.ch)"])
    }

    @Test(arguments: [
        ("#idee", ["idee"]),
        ("Text #Ferien/2026 und #ferien/2026", ["Ferien/2026"]),
        ("#123 ist keine Nummer-Tag", []),
        ("Mail a#b und Anker #", []),
        ("#Grüezi #über_alles", ["Grüezi", "über_alles"]),
    ])
    func tags(text: String, expected: [String]) {
        #expect(MarkdownSyntax.tags(in: text) == expected)
    }
}

struct MarkdownEditingTests {
    @Test func wrapEmptySelectionPutsCaretInside() {
        let edit = MarkdownEditing.toggleWrap("**", in: "ab", selection: NSRange(location: 1, length: 0))
        #expect(edit.applied(to: "ab") == "a****b")
        #expect(edit.selection == NSRange(location: 3, length: 0))
    }

    @Test func wrapAndUnwrapSelection() {
        let text = "ein Wort hier"
        let wrapped = MarkdownEditing.toggleWrap("**", in: text, selection: NSRange(location: 4, length: 4))
        let afterWrap = wrapped.applied(to: text)
        #expect(afterWrap == "ein **Wort** hier")
        #expect(wrapped.selection == NSRange(location: 6, length: 4))

        let unwrapped = MarkdownEditing.toggleWrap("**", in: afterWrap, selection: wrapped.selection)
        #expect(unwrapped.applied(to: afterWrap) == text)
        #expect(unwrapped.selection == NSRange(location: 4, length: 4))

        let selectedWithMarkers = MarkdownEditing.toggleWrap("**", in: afterWrap, selection: NSRange(location: 4, length: 8))
        #expect(selectedWithMarkers.applied(to: afterWrap) == text)
    }

    @Test func toggleChecklistOnSeveralLines() {
        let text = "Milch\n\nBrot\n- Käse"
        let edit = MarkdownEditing.toggleLineStyle(.checkbox, in: text, selection: NSRange(location: 0, length: (text as NSString).length))
        let result = edit.applied(to: text)
        #expect(result == "- [ ] Milch\n\n- [ ] Brot\n- [ ] Käse")

        let back = MarkdownEditing.toggleLineStyle(.checkbox, in: result, selection: NSRange(location: 0, length: (result as NSString).length))
        #expect(back.applied(to: result) == "Milch\n\nBrot\nKäse")
    }

    @Test func toggleBulletMovesCaret() {
        let edit = MarkdownEditing.toggleLineStyle(.bullet, in: "  Punkt", selection: NSRange(location: 4, length: 0))
        #expect(edit.applied(to: "  Punkt") == "  - Punkt")
        #expect(edit.selection == NSRange(location: 6, length: 0))
    }

    @Test func cycleHeadingLevels() {
        var text = "Titel"
        var selection = NSRange(location: 5, length: 0)
        var results: [String] = []
        for _ in 0..<4 {
            let edit = MarkdownEditing.cycleHeading(in: text, selection: selection)
            text = edit.applied(to: text)
            selection = edit.selection
            results.append(text)
        }
        #expect(results == ["# Titel", "## Titel", "### Titel", "Titel"])
        #expect(selection == NSRange(location: 5, length: 0))
    }

    @Test func toggleCheckboxOnlyOnTheBox() {
        let text = "- [ ] Milch\n- [x] Brot"
        let keep = NSRange(location: 0, length: 0)
        let on = try! #require(MarkdownEditing.toggleCheckbox(at: 3, in: text, keeping: keep))
        #expect(on.applied(to: text) == "- [x] Milch\n- [x] Brot")
        let off = try! #require(MarkdownEditing.toggleCheckbox(at: 15, in: text, keeping: keep))
        #expect(off.applied(to: text) == "- [ ] Milch\n- [ ] Brot")
        #expect(MarkdownEditing.toggleCheckbox(at: 8, in: text, keeping: keep) == nil)
    }

    @Test func returnContinuesOrEndsList() {
        let text = "- [x] Milch"
        let next = try! #require(MarkdownEditing.continueList(in: text, selection: NSRange(location: 11, length: 0)))
        let afterNext = next.applied(to: text)
        #expect(afterNext == "- [x] Milch\n- [ ] ")

        let end = try! #require(MarkdownEditing.continueList(in: afterNext, selection: next.selection))
        #expect(end.applied(to: afterNext) == "- [x] Milch\n")
        #expect(MarkdownEditing.continueList(in: "Text", selection: NSRange(location: 4, length: 0)) == nil)
    }

    @Test func tagQueryAndCompletion() {
        let text = "Heute #fer"
        let query = try! #require(MarkdownEditing.tagQuery(in: text, caret: 10))
        #expect(query.query == "fer")
        let edit = MarkdownEditing.completeTag("ferien", replacing: query.range, in: text)
        #expect(edit.applied(to: text) == "Heute #ferien ")
        #expect(edit.selection == NSRange(location: 14, length: 0))

        // Am Zeilenende: Leerzeichen einfügen, Cursor bleibt in der Zeile.
        let atLineEnd = "- Punkt #fa\nWeiter"
        let lineEndEdit = MarkdownEditing.completeTag("familie", replacing: NSRange(location: 8, length: 3), in: atLineEnd)
        #expect(lineEndEdit.applied(to: atLineEnd) == "- Punkt #familie \nWeiter")
        #expect(lineEndEdit.selection == NSRange(location: 17, length: 0))

        // Folgt schon ein Leerzeichen, wird keines verdoppelt.
        let beforeSpace = "#fa und"
        let spaceEdit = MarkdownEditing.completeTag("familie", replacing: NSRange(location: 0, length: 3), in: beforeSpace)
        #expect(spaceEdit.applied(to: beforeSpace) == "#familie und")
        #expect(spaceEdit.selection == NSRange(location: 9, length: 0))

        #expect(MarkdownEditing.tagQuery(in: "Heute #", caret: 7)?.query == "")
        #expect(MarkdownEditing.tagQuery(in: "a#b", caret: 3) == nil)
        #expect(MarkdownEditing.tagQuery(in: "kein tag", caret: 8) == nil)
    }
}

struct TagCollectionTests {
    @Test func collectsTagsAcrossFoldersSkippingSystemFolders() throws {
        let test = try TestVault()
        try test.write("#Ferien #idee", to: "Inbox/A.md")
        try test.write("#ferien", to: "Privat/B.md")
        try test.write("#geheim", to: "_Zuletzt gelöscht/x/C.md")
        let tags = test.vault.allTags()
        #expect(tags.map(\.name) == ["Ferien", "idee"])
        #expect(tags.first?.count == 2)
    }
}
