import Foundation
import Testing
@testable import HirniKit

struct VaultTests {
    @Test func folderTreeHidesInboxAndSystemFolders() throws {
        let test = try TestVault()
        try test.write("", to: "Privat/Ferien/Packliste.md")
        try test.write("", to: "Arbeit/x.md")
        try test.write("", to: "Privat/_Anhänge/bild.jpg")
        try test.write("", to: ".obsidian/config")

        let tree = try test.vault.folderTree()
        // «Vorlagen» ist ein normaler, sichtbarer Ordner.
        #expect(tree.map(\.name) == ["Arbeit", "Privat", "Vorlagen"])
        #expect(tree[1].children.map(\.name) == ["Ferien"])
        #expect(tree[1].children[0].childrenOrNil == nil)
    }

    @Test func notesAreListedNewestFirstWithPreview() throws {
        let test = try TestVault()
        try test.write("# Alt\nalter Inhalt", to: "Inbox/Alt.md")
        try test.write("Neuer Inhalt", to: "Inbox/Neu.md")
        try test.write("", to: "Inbox/bild.jpg")
        let old = test.vault.inboxURL.appending(path: "Alt.md")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old.path(percentEncoded: false)
        )

        let notes = try test.vault.notes(in: test.vault.inboxURL)
        #expect(notes.map(\.title) == ["Neu", "Alt"])
        #expect(notes[1].preview == "Alt alter Inhalt")
        let allDownloaded = notes.allSatisfy(\.isDownloaded)
        #expect(allDownloaded)
    }

    @Test func placeholdersAppearAsNotDownloadedNotes() throws {
        let test = try TestVault()
        try test.write("", to: "Inbox/.Unterwegs.md.icloud")

        let notes = try test.vault.notes(in: test.vault.inboxURL)
        #expect(notes.map(\.title) == ["Unterwegs"])
        #expect(notes[0].isDownloaded == false)
        #expect(notes[0].url.lastPathComponent == "Unterwegs.md")
    }

    @Test func createWriteReadNote() throws {
        let test = try TestVault()
        let url = try test.vault.createNote(in: test.vault.inboxURL)
        #expect(url.lastPathComponent == "Neue Notiz.md")
        let second = try test.vault.createNote(in: test.vault.inboxURL)
        #expect(second.lastPathComponent == "Neue Notiz 2.md")

        try test.vault.writeNote("Hallo hirni", to: url)
        #expect(try test.vault.readNote(at: url) == "Hallo hirni")
    }

    @Test func renameNoteKeepsContentAndAvoidsCollisions() throws {
        let test = try TestVault()
        try test.write("A", to: "Inbox/Einkauf.md")
        try test.write("B", to: "Inbox/Notiz.md")
        let note = test.vault.inboxURL.appending(path: "Notiz.md")

        let renamed = try test.vault.renameNote(at: note, to: "Einkauf")
        #expect(renamed.lastPathComponent == "Einkauf 2.md")
        #expect(try test.vault.readNote(at: renamed) == "B")
        #expect(!test.exists("Inbox/Notiz.md"))
    }

    @Test func renameOnlyChangingCase() throws {
        let test = try TestVault()
        try test.write("A", to: "Inbox/einkauf.md")
        let renamed = try test.vault.renameNote(at: test.vault.inboxURL.appending(path: "einkauf.md"), to: "Einkauf")

        #expect(renamed.lastPathComponent == "Einkauf.md")
        let names = try FileManager.default.contentsOfDirectory(atPath: test.vault.inboxURL.path(percentEncoded: false))
        #expect(names == ["Einkauf.md"])
    }

    @Test func createAndRenameFolder() throws {
        let test = try TestVault()
        let folder = try test.vault.createFolder(in: test.vault.root, name: "_Privat")
        #expect(folder.lastPathComponent == "Privat") // kein Systemordner aus Versehen
        try test.write("x", to: "Privat/Notiz.md")

        let renamed = try test.vault.renameFolder(at: folder, to: "Persönlich")
        #expect(test.exists("Persönlich/Notiz.md"))
        #expect(renamed.lastPathComponent == "Persönlich")
    }
}
