import Foundation
import Testing
@testable import HirniKit

struct RowPageTests {
    @Test func createsPageNextToDatabaseAndFindsItAgain() throws {
        let test = try TestVault()
        let database = try test.vault.createDatabase(in: test.vault.inboxURL, title: "Ausgaben")

        let page = try test.vault.rowPage(for: database, rowID: "k3f9a2c1", title: "Restaurant Bern")
        #expect(page.lastPathComponent == "Restaurant Bern.md")
        #expect(test.exists("Inbox/Ausgaben/Restaurant Bern.md"))
        #expect(try test.vault.readNote(at: page) == "---\nhirni-zeile: k3f9a2c1\n---\n")

        // Zweiter Aufruf: dieselbe Seite, keine neue
        let again = try test.vault.rowPage(for: database, rowID: "k3f9a2c1", title: "Anders")
        #expect(again.resolvingSymlinksInPath() == page.resolvingSymlinksInPath())
        #expect(test.vault.rowPages(for: database).mapValues(\.lastPathComponent) == ["k3f9a2c1": "Restaurant Bern.md"])
    }

    @Test func pageIsFoundByIdNotByName() throws {
        let test = try TestVault()
        let database = try test.vault.createDatabase(in: test.vault.inboxURL, title: "Ausgaben")
        try test.write("---\nangepinnt: true\nhirni-zeile: abc\n---\nNotizen", to: "Inbox/Ausgaben/Umbenannt.md")
        try test.write("Ohne Kopf", to: "Inbox/Ausgaben/Andere.md")

        let pages = test.vault.rowPages(for: database)
        #expect(pages.keys.sorted() == ["abc"])
        #expect(pages["abc"]?.lastPathComponent == "Umbenannt.md")
    }

    @Test func sameTitleGetsNumberAndEmptyTitleFallsBack() throws {
        let test = try TestVault()
        let database = try test.vault.createDatabase(in: test.vault.inboxURL, title: "Ausgaben")
        _ = try test.vault.rowPage(for: database, rowID: "a", title: "Pizza")
        let second = try test.vault.rowPage(for: database, rowID: "b", title: "Pizza")
        let unnamed = try test.vault.rowPage(for: database, rowID: "c", title: "  ")
        #expect(second.lastPathComponent == "Pizza 2.md")
        #expect(unnamed.lastPathComponent == "Eintrag.md")
    }

    @Test func pagesFollowRenameAndMove() throws {
        let test = try TestVault()
        let database = try test.vault.createDatabase(in: test.vault.inboxURL, title: "Ausgaben")
        _ = try test.vault.rowPage(for: database, rowID: "a", title: "Pizza")

        let renamed = try test.vault.renameNote(at: database, to: "Ferien")
        #expect(test.exists("Inbox/Ferien/Pizza.md"))
        #expect(!test.exists("Inbox/Ausgaben"))

        let privat = try test.vault.createFolder(in: test.vault.root, name: "Privat")
        let moved = try test.vault.move(renamed, to: privat)
        #expect(test.exists("Privat/Ferien.hirnidb.md"))
        #expect(test.exists("Privat/Ferien/Pizza.md"))
        #expect(test.vault.rowPages(for: moved)["a"] != nil)
    }

    @Test func occupiedTargetFolderStaysUntouched() throws {
        let test = try TestVault()
        let database = try test.vault.createDatabase(in: test.vault.inboxURL, title: "Ausgaben")
        _ = try test.vault.rowPage(for: database, rowID: "a", title: "Pizza")
        try test.write("Eigene Notiz", to: "Inbox/Ferien/Packliste.md")

        _ = try test.vault.renameNote(at: database, to: "Ferien")
        #expect(test.exists("Inbox/Ausgaben/Pizza.md"))
        #expect(!test.exists("Inbox/Ferien/Pizza.md"))
    }
}
