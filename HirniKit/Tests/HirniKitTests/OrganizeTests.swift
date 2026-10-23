import Foundation
import Testing
@testable import HirniKit

struct FrontmatterTests {
    @Test func splitAndJoinRoundTrip() {
        let text = "---\nangepinnt: true\nquelle: Claude\n---\n# Titel\nText"
        let (header, body) = Frontmatter.split(text)
        #expect(header == "angepinnt: true\nquelle: Claude")
        #expect(body == "# Titel\nText")
        #expect(Frontmatter.join(header: header, body: body) == text)
    }

    @Test func textWithoutHeader() {
        #expect(Frontmatter.split("Nur Text").header == nil)
        #expect(Frontmatter.split("---\nkein Ende").header == nil)
        #expect(Frontmatter.split("--- nicht am Anfang").header == nil)
    }

    @Test func readsValuesWithQuotes() {
        let text = "---\nangepinnt: \"true\"\n---\n"
        #expect(Frontmatter.value("angepinnt", in: text) == "true")
        #expect(Frontmatter.value("fehlt", in: text) == nil)
    }

    @Test func settingAddsChangesAndRemoves() {
        let added = Frontmatter.setting("angepinnt", to: "true", in: "Text")
        #expect(added == "---\nangepinnt: true\n---\nText")

        let kept = Frontmatter.setting("angepinnt", to: "true", in: "---\nquelle: x\n---\nText")
        #expect(kept == "---\nquelle: x\nangepinnt: true\n---\nText")

        // Kopf wird leer → verschwindet ganz
        #expect(Frontmatter.setting("angepinnt", to: nil, in: added) == "Text")
        // Andere Zeilen bleiben stehen
        #expect(Frontmatter.setting("angepinnt", to: nil, in: kept) == "---\nquelle: x\n---\nText")
    }
}

struct OrganizeTests {
    @Test func moveNoteToFolder() throws {
        let test = try TestVault()
        try test.write("Inhalt", to: "Inbox/Einkauf.md")
        try test.write("", to: "Privat/.keep")
        let target = try test.vault.move(
            test.vault.inboxURL.appending(path: "Einkauf.md"), to: test.vault.root.appending(path: "Privat")
        )
        #expect(test.exists("Privat/Einkauf.md"))
        #expect(!test.exists("Inbox/Einkauf.md"))
        #expect(try test.vault.readNote(at: target) == "Inhalt")
    }

    @Test func moveAvoidsOverwriting() throws {
        let test = try TestVault()
        try test.write("neu", to: "Inbox/Einkauf.md")
        try test.write("alt", to: "Privat/Einkauf.md")
        let target = try test.vault.move(
            test.vault.inboxURL.appending(path: "Einkauf.md"), to: test.vault.root.appending(path: "Privat")
        )
        #expect(target.lastPathComponent == "Einkauf 2.md")
        #expect(try test.vault.readNote(at: test.vault.root.appending(path: "Privat/Einkauf.md")) == "alt")
    }

    @Test func moveToSameFolderDoesNothing() throws {
        let test = try TestVault()
        try test.write("x", to: "Inbox/Einkauf.md")
        let url = test.vault.inboxURL.appending(path: "Einkauf.md")
        #expect(try test.vault.move(url, to: test.vault.inboxURL) == url)
        #expect(test.exists("Inbox/Einkauf.md"))
    }

    @Test func moveFolderWithContentAndRefuseIntoItself() throws {
        let test = try TestVault()
        try test.write("x", to: "Privat/Ferien/Packliste.md")
        try test.write("", to: "Archiv/.keep")
        let privat = test.vault.root.appending(path: "Privat")

        #expect(throws: VaultError.self) {
            try test.vault.move(privat, to: privat.appending(path: "Ferien"))
        }
        try test.vault.move(privat, to: test.vault.root.appending(path: "Archiv"))
        #expect(test.exists("Archiv/Privat/Ferien/Packliste.md"))
    }

    @Test func duplicateIsNotPinned() throws {
        let test = try TestVault()
        try test.write("---\nangepinnt: true\n---\nText", to: "Inbox/Einkauf.md")
        let copy = try test.vault.duplicateNote(at: test.vault.inboxURL.appending(path: "Einkauf.md"))
        #expect(copy.lastPathComponent == "Einkauf Kopie.md")
        #expect(try test.vault.readNote(at: copy) == "Text")
    }

    @Test func pinnedNotesComeFirst() throws {
        let test = try TestVault()
        try test.write("alt", to: "Inbox/Alt.md")
        try test.write("neu", to: "Inbox/Neu.md")
        let old = test.vault.inboxURL.appending(path: "Alt.md")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old.path(percentEncoded: false)
        )
        let before = try #require(test.vault.modificationDate(of: old))
        try test.vault.setPinned(true, note: old)
        #expect(test.vault.modificationDate(of: old) == before)

        let notes = try test.vault.notes(in: test.vault.inboxURL)
        #expect(notes.map(\.title) == ["Alt", "Neu"])
        #expect(notes[0].isPinned)
        #expect(notes[0].preview == "alt") // der YAML-Kopf erscheint nicht in der Vorschau

        try test.vault.setPinned(false, note: old)
        #expect(try test.vault.readNote(at: old) == "alt")
    }
}
