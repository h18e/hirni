import Foundation
import Testing
@testable import HirniKit

struct SearchIndexTests {
    private func makeIndex() throws -> SearchIndex {
        let file = FileManager.default.temporaryDirectory.appending(path: "hirni-index-\(UUID().uuidString).sqlite")
        return try SearchIndex(fileURL: file)
    }

    @Test func findsWordsInTitleAndTextIgnoringCaseAndUmlauts() async throws {
        let test = try TestVault()
        try test.write("Wir fahren ans Meer. Über die Brücke.", to: "Privat/Sommerferien.md")
        try test.write("Einkauf: Milch", to: "Inbox/Einkauf.md")
        let index = try makeIndex()
        #expect(try await index.update(from: test.vault) == 2)

        let byText = try await index.search("ueber BRUCKE", vault: test.vault)
        #expect(byText.isEmpty) // «ue» ist kein «ü»
        let umlautless = try await index.search("uber brucke", vault: test.vault)
        #expect(umlautless.map(\.title) == ["Sommerferien"])

        let prefix = try await index.search("sommer", vault: test.vault)
        #expect(prefix.first?.folder == "Privat")

        let snippet = try #require(try await index.search("milch", vault: test.vault).first?.snippet)
        #expect(snippet.contains("\u{1}Milch\u{2}"))
    }

    @Test func titleMatchesRankFirst() async throws {
        let test = try TestVault()
        try test.write("Ferien Ferien Ferien", to: "Inbox/Notiz.md")
        try test.write("nichts", to: "Inbox/Ferien.md")
        let index = try makeIndex()
        try await index.update(from: test.vault)
        #expect(try await index.search("ferien", vault: test.vault).first?.title == "Ferien")
    }

    @Test func filterByFolderIncludesSubfolders() async throws {
        let test = try TestVault()
        try test.write("Plan", to: "Privat/Ferien/Plan.md")
        try test.write("Plan", to: "Privat_alt/Plan.md")
        try test.write("Plan", to: "Arbeit/Plan.md")
        let index = try makeIndex()
        try await index.update(from: test.vault)
        let hits = try await index.search("plan", in: "Privat", vault: test.vault)
        #expect(hits.map(\.folder) == ["Privat/Ferien"])
    }

    @Test func updatesOnlyChangedFilesAndForgetsDeletedOnes() async throws {
        let test = try TestVault()
        try test.write("alt", to: "Inbox/A.md")
        try test.write("bleibt", to: "Inbox/B.md")
        let index = try makeIndex()
        try await index.update(from: test.vault)
        #expect(try await index.update(from: test.vault) == 0)

        try await Task.sleep(for: .milliseconds(20))
        try test.write("neu", to: "Inbox/A.md")
        try FileManager.default.removeItem(at: test.vault.inboxURL.appending(path: "B.md"))
        #expect(try await index.update(from: test.vault) == 2)
        #expect(try await index.search("alt", vault: test.vault).isEmpty)
        #expect(try await index.search("neu", vault: test.vault).count == 1)
        #expect(try await index.search("bleibt", vault: test.vault).isEmpty)
    }

    @Test func tagsWithCountsAndChildren() async throws {
        let test = try TestVault()
        try test.write("#Ferien/2026 #idee", to: "Inbox/A.md")
        try test.write("#ferien", to: "Privat/B.md")
        try test.write("#geheim", to: "_Zuletzt gelöscht/x/C.md")
        let index = try makeIndex()
        try await index.update(from: test.vault)

        let tags = try await index.tags()
        // Gleich häufig → alphabetisch
        #expect(tags.map(\.name) == ["ferien", "Ferien/2026", "idee"])
        let withChildren = try await index.notes(withTag: "Ferien", vault: test.vault)
        #expect(withChildren.map(\.lastPathComponent) == ["A.md", "B.md"])
        let exact = try await index.notes(withTag: "ferien", includeChildren: false, vault: test.vault)
        #expect(exact.map(\.lastPathComponent) == ["B.md"])
    }

    @Test func findsDatabaseEntries() async throws {
        let test = try TestVault()
        let url = try test.vault.createDatabase(in: test.vault.inboxURL, title: "Ausgaben")
        var db = try test.vault.readDatabase(at: url)
        db.fields.append(Field(name: "Betrag", type: .number, format: .chf))
        db.rows = [Row(values: ["Name": "Pizza am See", "Betrag": "42.5"]), Row(values: ["Name": "Zug"])]
        try test.vault.writeDatabase(db, to: url)

        let index = try makeIndex()
        try await index.update(from: test.vault)
        let hit = try #require(try await index.search("pizza", vault: test.vault).first)
        #expect(hit.title == "Ausgaben")
        #expect(hit.url.lastPathComponent == "Ausgaben.hirnidb.md")
        #expect(hit.snippet.contains("42.50"))
    }

    @Test func oddInputIsSafe() async throws {
        let test = try TestVault()
        try test.write("Text", to: "Inbox/A.md")
        let index = try makeIndex()
        try await index.update(from: test.vault)
        for input in ["", "   ", "\"", "*", "a OR", "NOT text", "(", "#"] {
            _ = try await index.search(input, vault: test.vault)
        }
        // «NOT» ist hier ein gewöhnliches Wort, kein Befehl: Es müsste also vorkommen.
        #expect(try await index.search("NOT text", vault: test.vault).isEmpty)
        #expect(try await index.search("text", vault: test.vault).count == 1)
    }
}
