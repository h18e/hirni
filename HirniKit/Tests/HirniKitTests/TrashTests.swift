import Foundation
import Testing
@testable import HirniKit

struct TrashTests {
    @Test func deleteAndRestoreNote() throws {
        let test = try TestVault()
        try test.write("Inhalt", to: "Privat/Einkauf.md")
        let note = test.vault.root.appending(path: "Privat/Einkauf.md")

        try test.vault.moveToTrash(note)
        #expect(!test.exists("Privat/Einkauf.md"))

        let entries = try test.vault.trashEntries()
        #expect(entries.count == 1)
        #expect(entries[0].name == "Einkauf.md")
        #expect(entries[0].originalPath == "Privat/Einkauf.md")

        let restored = try test.vault.restore(entries[0])
        #expect(restored.lastPathComponent == "Einkauf.md")
        #expect(try test.vault.readNote(at: restored) == "Inhalt")
        #expect(try test.vault.trashEntries().isEmpty)
    }

    @Test func sameNameFromDifferentFoldersDoesNotCollide() throws {
        let test = try TestVault()
        try test.write("A", to: "A/Notiz.md")
        try test.write("B", to: "B/Notiz.md")
        try test.vault.moveToTrash(test.vault.root.appending(path: "A/Notiz.md"))
        try test.vault.moveToTrash(test.vault.root.appending(path: "B/Notiz.md"))

        #expect(Set(try test.vault.trashEntries().map(\.originalPath)) == ["A/Notiz.md", "B/Notiz.md"])
    }

    @Test func restoreRecreatesMissingFolderAndAvoidsOverwriting() throws {
        let test = try TestVault()
        try test.write("alt", to: "Privat/Einkauf.md")
        try test.vault.moveToTrash(test.vault.root.appending(path: "Privat/Einkauf.md"))
        try test.write("neu", to: "Privat/Einkauf.md")

        let restored = try test.vault.restore(try test.vault.trashEntries()[0])
        #expect(restored.lastPathComponent == "Einkauf 2.md")
        #expect(try test.vault.readNote(at: test.vault.root.appending(path: "Privat/Einkauf.md")) == "neu")

        try FileManager.default.removeItem(at: test.vault.root.appending(path: "Privat"))
        try test.write("x", to: "Privat/Weg.md")
        try test.vault.moveToTrash(test.vault.root.appending(path: "Privat"))
        #expect(!test.exists("Privat"))
        let folderEntry = try test.vault.trashEntries()[0]
        #expect(folderEntry.isFolder)
        try test.vault.restore(folderEntry)
        #expect(test.exists("Privat/Weg.md"))
    }

    @Test func purgeRemovesOnlyOldEntries() throws {
        let test = try TestVault()
        try test.write("", to: "Inbox/Alt.md")
        try test.write("", to: "Inbox/Neu.md")
        let now = Date()
        try test.vault.moveToTrash(test.vault.inboxURL.appending(path: "Alt.md"), now: now.addingTimeInterval(-31 * 86400))
        try test.vault.moveToTrash(test.vault.inboxURL.appending(path: "Neu.md"), now: now.addingTimeInterval(-29 * 86400))

        try test.vault.purgeTrash(now: now)
        #expect(try test.vault.trashEntries().map(\.name) == ["Neu.md"])
    }

    @Test func itemDroppedIntoTrashWithoutInfoGoesBackToInbox() throws {
        let test = try TestVault()
        try test.write("x", to: "_Zuletzt gelöscht/Lose.md")

        let entry = try #require(try test.vault.trashEntries().first)
        #expect(entry.containerURL == nil)
        try test.vault.restore(entry)
        #expect(test.exists("Inbox/Lose.md"))
    }
}

struct EmptyTrashTests {
    @Test func emptiesEverything() throws {
        let test = try TestVault()
        let note = try test.vault.createNote(in: test.vault.inboxURL, title: "A")
        let db = try test.vault.createDatabase(in: test.vault.inboxURL, title: "B")
        let folder = try test.vault.createFolder(in: test.vault.root, name: "C")
        for url in [note, db, folder] { try test.vault.moveToTrash(url) }
        #expect(try test.vault.trashEntries().count == 3)
        #expect(try test.vault.emptyTrash() == 3)
        #expect(try test.vault.trashEntries().isEmpty)
        #expect(test.exists("_Zuletzt gelöscht"))
    }
}
