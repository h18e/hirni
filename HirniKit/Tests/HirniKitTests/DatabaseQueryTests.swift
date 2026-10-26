import Foundation
import Testing
@testable import HirniKit

struct DatabaseQueryTests {
    let db = Database(
        fields: [
            Field(name: "Name", type: .text),
            Field(name: "Betrag", type: .number, format: .chf),
            Field(name: "Kategorie", type: .select, options: ["Essen", "Reisen", "Freizeit"]),
            Field(name: "Datum", type: .date),
            Field(name: "Bezahlt", type: .checkbox),
            Field(name: "Tags", type: .multiSelect, options: ["Ferien", "Kinder"]),
        ],
        rows: [
            Row(id: "1", values: ["Name": "Pizza", "Betrag": "42.5", "Kategorie": "Essen", "Datum": "2026-10-24", "Bezahlt": "ja", "Tags": "Ferien, Kinder"]),
            Row(id: "2", values: ["Name": "Zug", "Betrag": "18", "Kategorie": "Reisen", "Datum": "2026-09-30", "Bezahlt": "nein", "Tags": "Ferien"]),
            Row(id: "3", values: ["Name": "Kino", "Betrag": "30", "Kategorie": "Freizeit", "Datum": "2026-10-02"]),
            Row(id: "4", values: ["Name": "Gipfeli", "Kategorie": "Essen"]),
        ]
    )

    private func names(_ view: SavedView) -> [String] {
        DatabaseQuery.run(view, on: db).rows.map { $0["Name"] }
    }

    @Test func noViewShowsEverythingInFileOrder() {
        #expect(DatabaseQuery.run(nil, on: db).rows.map(\.id) == ["1", "2", "3", "4"])
    }

    @Test func filtersByType() {
        var view = SavedView(name: "x")
        view.filters = [FilterRule(field: "Betrag", condition: .greater, value: "20")]
        #expect(names(view) == ["Pizza", "Kino"])

        view.filters = [FilterRule(field: "Tags", condition: .contains, value: "ferien")]
        #expect(names(view) == ["Pizza", "Zug"])

        view.filters = [FilterRule(field: "Datum", condition: .after, value: "2026-10-01")]
        #expect(names(view) == ["Pizza", "Kino"])

        view.filters = [FilterRule(field: "Bezahlt", condition: .unchecked)]
        #expect(names(view) == ["Zug", "Kino", "Gipfeli"])

        view.filters = [FilterRule(field: "Betrag", condition: .isEmpty)]
        #expect(names(view) == ["Gipfeli"])

        view.filters = [FilterRule(field: "Name", condition: .contains, value: "I")]
        #expect(names(view) == ["Pizza", "Kino", "Gipfeli"])
    }

    @Test func severalFiltersMustAllMatchAndIncompleteRulesAreIgnored() {
        var view = SavedView(name: "x")
        view.filters = [
            FilterRule(field: "Kategorie", condition: .equals, value: "Essen"),
            FilterRule(field: "Betrag", condition: .isNotEmpty),
            FilterRule(field: "Name", condition: .contains, value: ""),      // noch ohne Wert
            FilterRule(field: "Gibt es nicht", condition: .equals, value: "x"),
        ]
        #expect(names(view) == ["Pizza"])
    }

    @Test func newRowsStayVisibleDespiteFilter() {
        var view = SavedView(name: "x")
        view.filters = [FilterRule(field: "Kategorie", condition: .equals, value: "Reisen")]
        #expect(DatabaseQuery.run(view, on: db, alwaysShowing: ["4"]).rows.map(\.id) == ["2", "4"])
    }

    @Test func sortsTypedWithEmptyValuesLast() {
        var view = SavedView(name: "x")
        view.sorts = [SortRule(field: "Betrag")]
        #expect(names(view) == ["Zug", "Kino", "Pizza", "Gipfeli"])
        view.sorts = [SortRule(field: "Betrag", descending: true)]
        #expect(names(view) == ["Pizza", "Kino", "Zug", "Gipfeli"])
        view.sorts = [SortRule(field: "Datum")]
        #expect(names(view) == ["Zug", "Kino", "Pizza", "Gipfeli"])
        // Auswahl in Reihenfolge der Optionen, dann nach Name
        view.sorts = [SortRule(field: "Kategorie"), SortRule(field: "Name")]
        #expect(names(view) == ["Gipfeli", "Pizza", "Zug", "Kino"])
    }

    @Test func groupsBySelectMultiSelectCheckboxAndMonth() {
        var view = SavedView(name: "x")
        view.groupBy = "Kategorie"
        let byCategory = DatabaseQuery.run(view, on: db).groups
        #expect(byCategory.map(\.title) == ["Essen", "Reisen", "Freizeit"])
        #expect(byCategory[0].rows.map(\.id) == ["1", "4"])

        view.groupBy = "Tags"
        let byTag = DatabaseQuery.run(view, on: db).groups
        #expect(byTag.map(\.title) == ["Ferien", "Kinder", "Ohne Tags"])
        #expect(byTag[0].rows.count == 2)

        view.groupBy = "Bezahlt"
        #expect(DatabaseQuery.run(view, on: db).groups.map(\.title) == ["Angehakt", "Nicht angehakt"])

        view.groupBy = "Datum"
        let byMonth = DatabaseQuery.run(view, on: db).groups
        #expect(byMonth.map(\.title) == ["September 2026", "Oktober 2026", "Ohne Datum"])
        #expect(byMonth[1].rows.count == 2)
    }

    @Test func aggregates() {
        let betrag = db.fields[1]
        #expect(DatabaseQuery.compute(.sum, field: betrag, rows: db.rows) == 90.5)
        #expect(DatabaseQuery.compute(.count, field: betrag, rows: db.rows) == 3)
        #expect(DatabaseQuery.compute(.average, field: betrag, rows: db.rows).map { ($0 * 100).rounded() / 100 } == 30.17)
        #expect(DatabaseQuery.compute(.min, field: betrag, rows: db.rows) == 18)
        #expect(DatabaseQuery.compute(.max, field: betrag, rows: db.rows) == 42.5)
        #expect(DatabaseQuery.compute(.count, field: db.fields[4], rows: db.rows) == 1) // angehakte
        #expect(DatabaseQuery.display(.sum, field: betrag, rows: []) == "–")
        #expect(DatabaseQuery.display(.sum, field: betrag, rows: db.rows).hasSuffix("90.50"))
    }
}

struct SavedViewFileTests {
    @Test func viewsRoundTripAndFollowFieldRenames() throws {
        var db = Database(fields: [Field(name: "Betrag", type: .number), Field(name: "Notiz", type: .text)])
        var view = SavedView(name: "Teuer")
        view.filters = [FilterRule(field: "Betrag", condition: .greater, value: "100")]
        view.sorts = [SortRule(field: "Betrag", descending: true)]
        view.aggregates = ["Betrag": .sum]
        view.hiddenFields = ["Notiz"]
        db.views = [view, SavedView(name: "Alle")]

        let text = DatabaseFile.serialize(db)
        #expect(text.contains("ansichten:"))
        #expect(text.contains(#""bedingung":">""#))
        let back = try DatabaseFile.parse(text)
        #expect(back.views == db.views)
        #expect(back.otherHeaderLines.isEmpty)

        view.renameField("Betrag", to: "Preis")
        view.renameField("Notiz", to: nil)
        #expect(view.filters?.first?.field == "Preis")
        #expect(view.aggregates == ["Preis": .sum])
        #expect(view.hiddenFields == [])
    }

    @Test func brokenViewDoesNotBreakTheDatabase() throws {
        let text = """
        ---
        hirni-datenbank: 1
        felder:
          - {"name": "Name", "typ": "text"}
        ansichten:
          - {"name": 42}
          - {"name": "Gut", "typ": "tabelle"}
        ---
        | id | Name |
        |---|---|
        """
        let db = try DatabaseFile.parse(text)
        #expect(db.views.map(\.name) == ["Gut"])
    }
}

struct OptionRenameTests {
    @Test func renamesSelectAndMultiSelectValues() {
        let renames = ["Essen": "Verpflegung"]
        #expect(CellValue.renamingOptions("Essen", renames, type: .select) == "Verpflegung")
        #expect(CellValue.renamingOptions("Reisen", renames, type: .select) == "Reisen")
        #expect(CellValue.renamingOptions("Essen, Kinder", renames, type: .multiSelect) == "Verpflegung, Kinder")
        #expect(CellValue.renamingOptions("Essen", renames, type: .text) == "Essen")
    }

    @Test func renamesFilterValues() {
        var view = SavedView(name: "Essen")
        view.filters = [FilterRule(field: "Kategorie", condition: .equals, value: "Essen"),
                        FilterRule(field: "Name", condition: .equals, value: "Essen")]
        view.renameOptions(of: "Kategorie", ["Essen": "Verpflegung"])
        #expect(view.filters?.map(\.value) == ["Verpflegung", "Essen"])
    }
}
