import Foundation
import Testing
@testable import HirniKit

struct DatabaseFileTests {
    let sample = """
    ---
    hirni-datenbank: 1
    felder:
      - {"name": "Name", "typ": "text"}
      - {"name": "Betrag", "typ": "zahl", "format": "chf"}
      - {"name": "Kategorie", "typ": "auswahl", "optionen": ["Essen", "Reisen"]}
    tags: [ausgaben]
    ---
    Meine Ausgaben 2026.

    | id | Name | Betrag | Kategorie |
    |---|---|---|---|
    | a1 | Pizza \\| Bier | 42.5 | Essen |
    | b2 | Zug<br>Bern | 18 | Reisen |

    Ende der Datei.
    """

    @Test func parsesFieldsRowsAndSurroundingText() throws {
        let db = try DatabaseFile.parse(sample)
        #expect(db.fields.map(\.name) == ["Name", "Betrag", "Kategorie"])
        #expect(db.fields[1].format == .chf)
        #expect(db.fields[2].options == ["Essen", "Reisen"])
        #expect(db.rows.map(\.id) == ["a1", "b2"])
        #expect(db.rows[0]["Name"] == "Pizza | Bier")
        #expect(db.rows[1]["Name"] == "Zug\nBern")
        #expect(db.otherHeaderLines == ["tags: [ausgaben]"])
        #expect(db.textBefore.contains("Meine Ausgaben"))
        #expect(db.textAfter.contains("Ende der Datei"))
    }

    @Test func roundTripIsStable() throws {
        let db = try DatabaseFile.parse(sample)
        let once = DatabaseFile.serialize(db)
        let twice = DatabaseFile.serialize(try DatabaseFile.parse(once))
        #expect(once == twice)
        #expect(try DatabaseFile.parse(once) == db)
        #expect(once.contains("| a1 | Pizza \\| Bier | 42.5 | Essen |"))
    }

    @Test func backslashesSurvive() throws {
        var db = Database(fields: [Field(name: "Pfad", type: .text)])
        db.rows = [Row(id: "x", values: ["Pfad": #"C:\Ordner\|Datei"#])]
        let back = try DatabaseFile.parse(DatabaseFile.serialize(db))
        #expect(back.rows[0]["Pfad"] == #"C:\Ordner\|Datei"#)
    }

    @Test func columnsAddedByHandBecomeTextFieldsAndMissingIDsAreCreated() throws {
        let text = """
        ---
        hirni-datenbank: 1
        felder:
          - {"name": "Name", "typ": "text"}
        ---
        | id | Notiz | Name |
        |---|---|---|
        |  | neu | Claude |
        | a | x | y |
        | a | doppelt | z |
        """
        let db = try DatabaseFile.parse(text)
        #expect(db.fields.map(\.name) == ["Name", "Notiz"])
        #expect(db.rows.count == 3)
        #expect(db.rows[0]["Name"] == "Claude")
        #expect(!db.rows[0].id.isEmpty)
        #expect(Set(db.rows.map(\.id)).count == 3)
    }

    @Test func emptyDatabaseAndErrors() throws {
        let empty = Database(fields: [Field(name: "Name", type: .text)])
        let text = DatabaseFile.serialize(empty)
        #expect(try DatabaseFile.parse(text) == empty)

        #expect(throws: DatabaseFileError.notADatabase) { try DatabaseFile.parse("# Nur eine Notiz") }
        #expect(throws: DatabaseFileError.self) {
            try DatabaseFile.parse("---\nhirni-datenbank: 1\nfelder:\n  - kaputt\n---\n")
        }
    }
}

struct CellValueTests {
    @Test(arguments: [
        ("42.5", 42.5), ("42,50", 42.5), ("CHF 1'200.00", 1200.0), ("1,200.50", 1200.5), ("-3", -3.0), ("12 %", 12.0),
    ])
    func parsesNumbers(raw: String, expected: Double) {
        #expect(CellValue.number(raw) == expected)
    }

    @Test func numberRawAndDisplay() {
        #expect(CellValue.raw(number: 42.5) == "42.5")
        #expect(CellValue.raw(number: 18) == "18")
        #expect(CellValue.raw(number: 0.1 + 0.2) == "0.3")
        // Zwischen «CHF» und Betrag steht ein geschütztes Leerzeichen.
        let chf = CellValue.display(number: 1200.5, format: .chf)
        #expect(chf.hasPrefix("CHF") && chf.hasSuffix("1'200.50"))
        #expect(CellValue.display(number: 12, format: .percent).contains("12"))
        #expect(CellValue.number("") == nil)
        #expect(CellValue.number("abc") == nil)
    }

    @Test func datesRoundTrip() throws {
        let day = try #require(CellValue.date("2026-10-24"))
        #expect(!day.includesTime)
        #expect(CellValue.raw(date: day) == "2026-10-24")

        let withTime = try #require(CellValue.date("2026-10-24 14:30"))
        #expect(withTime.includesTime)
        #expect(CellValue.raw(date: withTime) == "2026-10-24 14:30")

        let range = try #require(CellValue.date("2026-10-24/2026-10-26"))
        #expect(range.end != nil)
        #expect(CellValue.raw(date: range) == "2026-10-24/2026-10-26")

        #expect(CellValue.raw(date: try #require(CellValue.date("24.10.2026"))) == "2026-10-24")
        #expect(CellValue.date("morgen") == nil)
        #expect(CellValue.date("2026-13-40") == nil)
    }

    @Test func checkboxAndLists() {
        #expect(CellValue.bool("ja") && CellValue.bool("X") && !CellValue.bool("nein") && !CellValue.bool(""))
        #expect(CellValue.list(" Ferien, Kinder ,, ") == ["Ferien", "Kinder"])
        #expect(CellValue.raw(list: ["A", "B"]) == "A, B")
    }

    @Test func fitsTypeForWarnings() {
        let select = Field(name: "K", type: .select, options: ["Essen"])
        #expect(CellValue.fits("Essen", select))
        #expect(!CellValue.fits("Reisen", select))
        #expect(CellValue.fits("", Field(name: "Z", type: .number)))
        #expect(!CellValue.fits("viel", Field(name: "Z", type: .number)))
        #expect(CellValue.fits("https://hebera.ch", Field(name: "U", type: .url)))
    }
}

struct DatabaseVaultTests {
    @Test func createListRenameDuplicate() throws {
        let test = try TestVault()
        let url = try test.vault.createDatabase(in: test.vault.inboxURL, title: "Ausgaben")
        #expect(url.lastPathComponent == "Ausgaben.hirnidb.md")
        #expect(Vault.title(of: url) == "Ausgaben")

        var db = try test.vault.readDatabase(at: url)
        #expect(db.fields.map(\.name) == ["Name"])
        db.rows.append(Row(values: ["Name": "Pizza"]))
        try test.vault.writeDatabase(db, to: url)

        let listed = try test.vault.notes(in: test.vault.inboxURL)
        #expect(listed.map(\.title) == ["Ausgaben"])
        #expect(listed[0].isDatabase)
        #expect(listed[0].preview == "Datenbank · 1 Eintrag")

        let renamed = try test.vault.renameNote(at: url, to: "Ferien-Ausgaben")
        #expect(renamed.lastPathComponent == "Ferien-Ausgaben.hirnidb.md")

        let copy = try test.vault.duplicateNote(at: renamed)
        #expect(copy.lastPathComponent == "Ferien-Ausgaben Kopie.hirnidb.md")
        #expect(try test.vault.readDatabase(at: copy).rows.count == 1)
    }

    @Test func numbersGoBeforeTheDatabaseSuffix() throws {
        let test = try TestVault()
        let first = try test.vault.createDatabase(in: test.vault.inboxURL)
        let second = try test.vault.createDatabase(in: test.vault.inboxURL)
        #expect(second.lastPathComponent == "Neue Datenbank 2.hirnidb.md")
        #expect(Vault.isDatabase(second))
        #expect(Vault.title(of: second) == "Neue Datenbank 2")

        // Umbenennen auf einen belegten Namen, Verschieben, Duplizieren, Wiederherstellen
        let renamed = try test.vault.renameNote(at: second, to: "Neue Datenbank")
        #expect(renamed.lastPathComponent == "Neue Datenbank 2.hirnidb.md")
        try test.write("", to: "Privat/.keep")
        _ = try test.vault.createDatabase(in: test.vault.root.appending(path: "Privat"))
        let moved = try test.vault.move(first, to: test.vault.root.appending(path: "Privat"))
        #expect(moved.lastPathComponent == "Neue Datenbank 2.hirnidb.md")
        let copy1 = try test.vault.duplicateNote(at: moved)
        let copy2 = try test.vault.duplicateNote(at: moved)
        #expect(copy1.lastPathComponent == "Neue Datenbank 2 Kopie.hirnidb.md")
        #expect(copy2.lastPathComponent == "Neue Datenbank 2 Kopie 2.hirnidb.md")

        try test.vault.moveToTrash(copy2)
        _ = try test.vault.duplicateNote(at: moved) // belegt jetzt «… Kopie 2»
        let restored = try test.vault.restore(try #require(try test.vault.trashEntries().first))
        #expect(restored.lastPathComponent == "Neue Datenbank 2 Kopie 2 2.hirnidb.md") // wie bei Notizen
    }

    @Test func splitFileNames() {
        #expect(FileNaming.split("A.hirnidb.md") == ("A", "hirnidb.md"))
        #expect(FileNaming.split("A.md") == ("A", "md"))
        #expect(FileNaming.split("Ordner") == ("Ordner", nil))
    }

    @Test func databasesAreNotNotesForTagsAndIndex() throws {
        let test = try TestVault()
        _ = try test.vault.createDatabase(in: test.vault.inboxURL)
        #expect(test.vault.allNoteURLs().isEmpty)
    }
}

struct DatabaseMergeTests {
    let base = Database(fields: [Field(name: "Name", type: .text), Field(name: "Betrag", type: .number)], rows: [
        Row(id: "a", values: ["Name": "Pizza", "Betrag": "20"]),
        Row(id: "b", values: ["Name": "Zug", "Betrag": "18"]),
    ])

    @Test func differentCellsAndNewRowsFromBothSides() {
        var mine = base
        mine.rows[0]["Betrag"] = "22"
        mine.rows.append(Row(id: "m", values: ["Name": "Kino"]))
        var theirs = base
        theirs.rows[0]["Name"] = "Pizza Margherita"
        theirs.rows.insert(Row(id: "t", values: ["Name": "Bus"]), at: 1)

        let result = DatabaseMerge.merge(base: base, mine: mine, theirs: theirs)
        #expect(result.conflicts == 0)
        #expect(result.database.rows.map(\.id) == ["a", "t", "b", "m"])
        #expect(result.database.rows[0]["Name"] == "Pizza Margherita")
        #expect(result.database.rows[0]["Betrag"] == "22")
    }

    @Test func sameCellBothChangedKeepsMineAndCounts() {
        var mine = base
        mine.rows[1]["Betrag"] = "19"
        var theirs = base
        theirs.rows[1]["Betrag"] = "25"
        let result = DatabaseMerge.merge(base: base, mine: mine, theirs: theirs)
        #expect(result.conflicts == 1)
        #expect(result.database.rows[1]["Betrag"] == "19")
    }

    @Test func deletionsAndFieldChanges() {
        var mine = base
        mine.rows.removeAll { $0.id == "a" }
        var theirs = base
        theirs.rows.removeAll { $0.id == "b" }
        theirs.fields.append(Field(name: "Kategorie", type: .select, options: ["Essen"]))

        let result = DatabaseMerge.merge(base: base, mine: mine, theirs: theirs)
        #expect(result.database.rows.isEmpty)
        #expect(result.database.fields.map(\.name) == ["Name", "Betrag", "Kategorie"])
    }

    @Test func editedHereButDeletedElsewhereIsKept() {
        var mine = base
        mine.rows[0]["Betrag"] = "99"
        var theirs = base
        theirs.rows.removeAll { $0.id == "a" }
        let result = DatabaseMerge.merge(base: base, mine: mine, theirs: theirs)
        #expect(result.database.rows.map(\.id) == ["a", "b"])
        #expect(result.conflicts == 1)
    }
}

struct FieldOrderTests {
    @Test func movesFieldAndKeepsValues() throws {
        var db = Database(
            fields: [Field(name: "A", type: .text), Field(name: "B", type: .text), Field(name: "C", type: .text)],
            rows: [Row(id: "r1", values: ["A": "1", "B": "2", "C": "3"])]
        )
        db.moveField("C", before: "A")
        #expect(db.fields.map(\.name) == ["C", "A", "B"])
        db.moveField("C", before: nil)
        #expect(db.fields.map(\.name) == ["A", "B", "C"])
        db.moveField("A", before: "C")
        #expect(db.fields.map(\.name) == ["B", "A", "C"])
        db.moveField("X", before: "A")
        #expect(db.fields.map(\.name) == ["B", "A", "C"])

        // In der Datei stehen die Spalten danach in der neuen Reihenfolge.
        let text = DatabaseFile.serialize(db)
        #expect(text.contains("| id | B | A | C |"))
        #expect(try DatabaseFile.parse(text).rows.first?["A"] == "1")
    }
}

struct ListViewTests {
    @Test func listViewRoundTripsAsListe() throws {
        var db = Database(fields: [Field(name: "Name", type: .text)])
        db.views = [SavedView(name: "Kurz", kind: .list)]
        let text = DatabaseFile.serialize(db)
        #expect(text.contains(#""typ":"liste""#))
        #expect(try DatabaseFile.parse(text).views.first?.kind == .list)
    }
}
