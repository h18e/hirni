import Foundation
import Testing
@testable import HirniKit

struct FileNamingTests {
    @Test(arguments: [
        ("Einkauf", "Einkauf"),
        ("  Einkauf  ", "Einkauf"),
        ("Bern/Thun", "Bern-Thun"),
        ("12:30 Termin", "12-30 Termin"),
        (".versteckt", "versteckt"),
        ("", "Ohne Titel"),
        ("   ", "Ohne Titel"),
        ("Zeile 1\nZeile 2", "Zeile 1 Zeile 2"),
    ])
    func sanitizesTitles(input: String, expected: String) {
        #expect(FileNaming.sanitized(input) == expected)
    }

    @Test func uniqueNamesGetNumbers() throws {
        let test = try TestVault()
        let inbox = test.vault.inboxURL
        try test.write("", to: "Inbox/Neue Notiz.md")
        try test.write("", to: "Inbox/Neue Notiz 2.md")

        let url = FileNaming.uniqueURL(in: inbox, baseName: "Neue Notiz", pathExtension: "md")
        #expect(url.lastPathComponent == "Neue Notiz 3.md")
    }

    @Test func iCloudPlaceholderCountsAsTaken() throws {
        let test = try TestVault()
        try test.write("", to: "Inbox/.Einkauf.md.icloud")

        let url = FileNaming.uniqueURL(in: test.vault.inboxURL, baseName: "Einkauf", pathExtension: "md")
        #expect(url.lastPathComponent == "Einkauf 2.md")
    }

    @Test func placeholderNames() {
        #expect(ICloudPlaceholder.realName(forPlaceholder: ".Einkauf.md.icloud") == "Einkauf.md")
        #expect(ICloudPlaceholder.realName(forPlaceholder: "Einkauf.md") == nil)
        #expect(ICloudPlaceholder.realName(forPlaceholder: ".icloud") == nil)
        #expect(ICloudPlaceholder.placeholderName(for: "A.md") == ".A.md.icloud")
    }
}

struct NotePreviewTests {
    @Test func skipsHeadingMarksAndBlankLines() {
        #expect(NotePreview.make(from: "# Titel\n\nErste Zeile\n- Punkt") == "Titel Erste Zeile Punkt")
    }

    @Test func skipsFrontmatter() {
        #expect(NotePreview.make(from: "---\nangepinnt: true\n---\nInhalt") == "Inhalt")
    }

    @Test func stripsChecklistMarks() {
        #expect(NotePreview.make(from: "- [ ] Milch\n- [x] Brot") == "Milch Brot")
    }

    @Test func truncatesLongText() {
        let preview = NotePreview.make(from: String(repeating: "a", count: 500))
        #expect(preview.count == NotePreview.maxLength + 1)
        #expect(preview.hasSuffix("…"))
    }
}
