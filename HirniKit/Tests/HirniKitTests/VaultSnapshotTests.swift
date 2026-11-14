import Foundation
import HirniKit
import Testing

struct VaultSnapshotTests {
    @Test func remembersFoldersAndNotesAcrossSaving() throws {
        let test = try TestVault()
        try test.write("# Titel\nVorschautext", to: "Inbox/Einkauf.md")
        try test.write("Ferienplan", to: "Privat/Ferien/Plan.md")
        let vault = test.vault

        var snapshot = VaultSnapshot()
        snapshot.record(folders: try vault.folderTree(), in: vault)
        snapshot.record(notes: try vault.notes(in: vault.inboxURL), in: vault.inboxURL, vault: vault)
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        try snapshot.save(to: file)

        let loaded = VaultSnapshot.load(from: file)
        #expect(loaded == snapshot)
        #expect(loaded.folderNodes(in: vault) == (try vault.folderTree()))
        let notes = try #require(loaded.notes(in: vault.inboxURL, vault: vault))
        #expect(notes.map(\.title) == ["Einkauf"])
        #expect(notes[0].preview == (try vault.notes(in: vault.inboxURL))[0].preview)
        #expect(notes.map(\.url) == (try vault.notes(in: vault.inboxURL)).map(\.url))
        #expect(loaded.notes(in: vault.root.appending(path: "Privat"), vault: vault) == nil)
    }

    @Test func forgetsListsOfDeletedFolders() throws {
        let test = try TestVault()
        try test.write("x", to: "Alt/Notiz.md")
        let vault = test.vault
        let old = vault.root.appending(path: "Alt", directoryHint: .isDirectory)
        var snapshot = VaultSnapshot()
        snapshot.record(notes: try vault.notes(in: old), in: old, vault: vault)
        try FileManager.default.removeItem(at: old)
        snapshot.record(folders: try vault.folderTree(), in: vault)
        #expect(snapshot.notes(in: old, vault: vault) == nil)
    }

    @Test func missingFileGivesEmptySnapshot() {
        #expect(VaultSnapshot.load(from: URL(filePath: "/gibt/es/nicht.json")).isEmpty)
    }
}
