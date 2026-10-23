import Foundation
import Testing
@testable import HirniKit

struct VaultLayoutTests {
    @Test(arguments: ["_Zuletzt gelöscht", "_Anhänge", ".obsidian", ".Trash"])
    func systemFoldersAreHidden(name: String) {
        #expect(VaultLayout.isSystemFolder(named: name))
    }

    @Test(arguments: ["Inbox", "Privat", "Ferien 2026", "a_b"])
    func normalFoldersAreVisible(name: String) {
        #expect(!VaultLayout.isSystemFolder(named: name))
    }

    @Test func prepareCreatesRequiredFoldersAndKeepsExistingFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "hirni-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let inbox = root.appending(path: VaultLayout.inboxFolderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let existingNote = inbox.appending(path: "Bestehend.md")
        try "Hallo".write(to: existingNote, atomically: true, encoding: .utf8)

        try VaultLayout.prepare(root: root)
        try VaultLayout.prepare(root: root) // zweimal aufrufen darf nichts kaputt machen

        for name in VaultLayout.requiredFolders {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: root.appending(path: name).path(percentEncoded: false),
                isDirectory: &isDirectory
            )
            #expect(exists && isDirectory.boolValue, "\(name) fehlt")
        }
        #expect(try String(contentsOf: existingNote, encoding: .utf8) == "Hallo")
    }
}
