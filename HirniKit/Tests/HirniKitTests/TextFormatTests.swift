import Foundation
import Testing
@testable import HirniKit

struct TextFormatTests {
    @Test func spansHideTags() {
        let text = #"Ein <u>Wort</u> und <span style="color:red">rot</span> und <mark>gelb</mark>"#
        let spans = MarkdownSyntax.spans(in: text)
        let ns = text as NSString
        func inner(_ kind: MarkdownSpan.Kind) -> String? {
            spans.first { $0.kind == kind }.map { ns.substring(with: $0.range) }
        }
        #expect(inner(.underline) == "Wort")
        #expect(inner(.textColor(.red)) == "rot")
        #expect(inner(.highlight) == "gelb")
        #expect(spans.filter { $0.kind == .hiddenMarker }.count == 6)
        #expect(MarkdownSyntax.plainText(text) == "Ein Wort und rot und gelb")
    }

    @Test func toggleTagOnSelectionAndInside() {
        let on = MarkdownEditing.toggleTag("u", in: "Ein Wort", selection: NSRange(location: 4, length: 4))
        #expect(on.applied(to: "Ein Wort") == "Ein <u>Wort</u>")
        #expect(on.selection == NSRange(location: 7, length: 4))
        let text = "Ein <u>Wort</u>"
        let off = MarkdownEditing.toggleTag("u", in: text, selection: NSRange(location: 7, length: 4))
        #expect(off.applied(to: text) == "Ein Wort")
        #expect(off.selection == NSRange(location: 4, length: 4))
        let caret = MarkdownEditing.toggleTag("u", in: text, selection: NSRange(location: 9, length: 0))
        #expect(caret.applied(to: text) == "Ein Wort")
    }

    @Test func wholeLinesKeepPrefixesAndSkipCode() {
        let text = "# Titel\n- [ ] Pendenz\n\n```\ncode\n```\n| a | b |\nText"
        let all = NSRange(location: 0, length: (text as NSString).length)
        let edit = MarkdownEditing.toggleTag("u", in: text, selection: all)
        let result = edit.applied(to: text)
        #expect(result == "# <u>Titel</u>\n- [ ] <u>Pendenz</u>\n\n```\ncode\n```\n| a | b |\n<u>Text</u>")
        let back = MarkdownEditing.toggleTag("u", in: result, selection: edit.selection)
        #expect(back.applied(to: result) == text)
        let bold = MarkdownEditing.toggleWrap("**", in: "- Eins\n- Zwei", selection: NSRange(location: 0, length: 13))
        #expect(bold.applied(to: "- Eins\n- Zwei") == "- **Eins**\n- **Zwei**")
    }

    @Test func colors() {
        let plain = "Ein Wort"
        let red = MarkdownEditing.setColor(.red, in: plain, selection: NSRange(location: 4, length: 4))
        let colored = red.applied(to: plain)
        #expect(colored == #"Ein <span style="color:red">Wort</span>"#)
        // Andere Farbe: bleibt ein Bereich.
        let blue = MarkdownEditing.setColor(.blue, in: colored, selection: red.selection)
        let recolored = blue.applied(to: colored)
        #expect(recolored == #"Ein <span style="color:blue">Wort</span>"#)
        let gone = MarkdownEditing.setColor(nil, in: recolored, selection: blue.selection)
        #expect(gone.applied(to: recolored) == plain)
        #expect(gone.selection == NSRange(location: 4, length: 4))

        let lines = "- Eins\nZwei"
        let block = MarkdownEditing.setColor(.green, in: lines, selection: NSRange(location: 0, length: 11))
        #expect(block.applied(to: lines) == #"- <span style="color:green">Eins</span>"# + "\n" + #"<span style="color:green">Zwei</span>"#)
    }

    @Test func elsewhere() throws {
        let test = try TestVault()
        try test.write(#"- [ ] <u>Wichtig</u> #büro"# + "\n" + #"<span style="color:red">Rot</span> <mark>Gelb</mark> <u>Unter</u>"# + "\n", to: "Inbox/A.md")
        #expect(test.vault.allTasks().first?.text == "Wichtig #büro")
        let note = test.vault.inboxURL.appending(path: "A.md")
        let html = try test.vault.html(ofNote: note)
        #expect(html.contains("<u>Unter</u>"))
        #expect(html.contains("<mark>Gelb</mark>"))
        #expect(html.contains(#"<span style="color:red">Rot</span>"#))
        #expect(NotePreview.make(from: "<u>Unter</u>").hasPrefix("Unter"))
        #expect(MarkdownSyntax.headings(in: "# <u>Titel</u>").first?.title == "Titel")
    }
}

struct NoteLinkTests {
    @Test func survivesRenameMoveAndRefreshesLabel() throws {
        let test = try TestVault()
        try test.write("Inhalt\n", to: "Inbox/Ziel.md")
        var target = test.vault.inboxURL.appending(path: "Ziel.md")
        let before = test.vault.modificationDate(of: target)
        let markdown = try test.vault.linkMarkdown(to: target)
        #expect(markdown.hasPrefix("[Ziel](hirni://notiz?id="))
        let after = try #require(test.vault.modificationDate(of: target))
        #expect(abs(after.timeIntervalSince(try #require(before))) < 0.01)
        #expect(try test.vault.readNote(at: target).contains("Inhalt"))

        let address = try #require(MarkdownSyntax.linkAddress(markdown))
        let link = try #require(URL(string: address))
        #expect(test.vault.resolve(link: link)?.lastPathComponent == "Ziel.md")

        target = try test.vault.renameNote(at: target, to: "Neuer Name")
        try FileManager.default.createDirectory(at: test.vault.root.appending(path: "Privat"), withIntermediateDirectories: true)
        let moved = test.vault.root.appending(path: "Privat/Neuer Name.md")
        try FileManager.default.moveItem(at: target, to: moved) // wie im Finder
        #expect(test.vault.resolve(link: link)?.lastPathComponent == "Neuer Name.md")

        let refreshed = test.vault.refreshingNoteLinks(in: "Siehe \(markdown).")
        #expect(refreshed.hasPrefix("Siehe [Neuer Name](hirni://notiz?id="))
        #expect(refreshed.contains("pfad=Privat/Neuer%20Name.md"))
        #expect(test.vault.refreshingNoteLinks(in: refreshed) == refreshed)
    }

    @Test func fixedLabelPathFallbackAndCopies() throws {
        let test = try TestVault()
        try test.write("Inhalt\n", to: "Inbox/Ziel.md")
        let target = test.vault.inboxURL.appending(path: "Ziel.md")
        let fixed = try test.vault.linkMarkdown(to: target, label: "hier")
        _ = try test.vault.renameNote(at: target, to: "Anders")
        #expect(test.vault.refreshingNoteLinks(in: fixed).hasPrefix("[hier]("))

        let copy = try test.vault.duplicateNote(at: test.vault.inboxURL.appending(path: "Anders.md"))
        let copied = try test.vault.readNote(at: copy)
        #expect(!copied.contains("hirni-id"))

        #expect(test.vault.resolve(link: URL(string: "hirni://notiz?id=fehlt&pfad=Inbox/Anders.md")!)?.lastPathComponent == "Anders.md")
        #expect(test.vault.resolve(link: URL(string: "hirni://notiz?id=fehlt&pfad=Inbox/Weg.md")!) == nil)
        #expect(test.vault.linkTargets(excluding: copy).map(\.title) == ["Anders"])
    }

    @Test func linksShowOnlyTheLabel() {
        let text = "[Ziel](hirni://notiz?id=abc&pfad=x.md) und [Web](https://a.ch)"
        let hidden = MarkdownSyntax.spans(in: text).filter { $0.kind == .hiddenMarker }
        #expect(hidden.count == 2)
        #expect(MarkdownSyntax.plainText(text) == "Ziel und [Web](https://a.ch)")
        #expect(MarkdownSyntax.link(at: 2, in: text)?.scheme == "hirni")
    }
}
