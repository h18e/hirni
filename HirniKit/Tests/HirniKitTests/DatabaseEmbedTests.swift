import Foundation
import Testing
@testable import HirniKit

struct DatabaseEmbedTests {
    @Test func findsBlocksWithDatabaseAndView() {
        let text = "Vorher\n```hirni-db\ndatenbank: Ausgaben\nansicht: Pro Monat\n```\nNachher\n```swift\nlet x = 1\n```\n```hirni-db\ndatenbank: Privat/Ferien\n```"
        let blocks = DatabaseEmbed.blocks(in: text)
        #expect(blocks.map(\.database) == ["Ausgaben", "Privat/Ferien"])
        #expect(blocks.map(\.view) == ["Pro Monat", nil])
        let ns = text as NSString
        #expect(ns.substring(with: blocks[0].closingLine) == "```")
        #expect(ns.substring(with: blocks[0].range).hasPrefix("```hirni-db"))
        #expect(ns.substring(with: blocks[0].range).hasSuffix("ansicht: Pro Monat\n```"))
    }

    @Test func unfinishedBlockIsIgnoredAndEmptyNameCounts() {
        #expect(DatabaseEmbed.blocks(in: "```hirni-db\ndatenbank: A").isEmpty)
        #expect(DatabaseEmbed.blocks(in: "```hirni-db\n```").first?.database == "")
    }

    @Test func markdownRoundTrip() {
        let text = DatabaseEmbed.markdown(database: "Ausgaben", view: "Alle")
        #expect(text == "```hirni-db\ndatenbank: Ausgaben\nansicht: Alle\n```")
        #expect(DatabaseEmbed.blocks(in: text).first?.view == "Alle")
        #expect(DatabaseEmbed.markdown(database: "A", view: nil) == "```hirni-db\ndatenbank: A\n```")
    }

    @Test func resolvesByPathSiblingAndName() throws {
        let test = try TestVault()
        let privat = try test.vault.createFolder(in: test.vault.root, name: "Privat")
        let inboxDB = try test.vault.createDatabase(in: test.vault.inboxURL, title: "Ausgaben")
        let privatDB = try test.vault.createDatabase(in: privat, title: "Ausgaben")
        let ferien = try test.vault.createDatabase(in: privat, title: "Ferien")
        let note = test.vault.inboxURL.appending(path: "Notiz.md")
        func name(_ url: URL?) -> String? { url.flatMap { test.vault.relativePath(of: $0) } }

        #expect(name(test.vault.resolveDatabase("Ausgaben", from: note)) == name(inboxDB))
        #expect(name(test.vault.resolveDatabase("Privat/Ausgaben", from: note)) == name(privatDB))
        #expect(name(test.vault.resolveDatabase("ferien", from: note)) == name(ferien))
        #expect(test.vault.resolveDatabase("Gibt es nicht", from: note) == nil)
        #expect(test.vault.resolveDatabase("../ausserhalb/x", from: note) == nil)

        #expect(test.vault.databaseReference(for: inboxDB, from: note) == "Ausgaben")
        #expect(test.vault.databaseReference(for: ferien, from: note) == "Privat/Ferien")
    }

    @Test func previewShowsDatabaseName() {
        let text = "Budget\n```hirni-db\ndatenbank: Privat/Ausgaben\nansicht: Alle\n```\nEnde"
        #expect(NotePreview.make(from: text) == "Budget [Datenbank: Ausgaben] Ende")
    }
}
