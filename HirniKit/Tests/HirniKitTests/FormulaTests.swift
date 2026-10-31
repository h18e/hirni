import Foundation
import Testing
@testable import HirniKit

struct FormulaTests {
    let database: Database = {
        var database = Database(fields: [
            Field(name: "Name", type: .text),
            Field(name: "Preis", type: .number, format: .chf),
            Field(name: "Menge", type: .number),
            Field(name: "Bezahlt", type: .checkbox),
            Field(name: "Von", type: .date),
            Field(name: "Bis", type: .date),
            Field(name: "Total", type: .formula, format: .chf, formula: "=[Preis] * [Menge]"),
            Field(name: "Anteil", type: .formula, format: .percent, formula: "RUNDEN([Total] / SUMME([Total]) * 100; 1)"),
        ])
        database.rows = [
            Row(id: "a", values: ["Name": "Pizza", "Preis": "12.5", "Menge": "2", "Bezahlt": "ja", "Von": "2026-10-01", "Bis": "2026-10-11"]),
            Row(id: "b", values: ["Name": "Wein", "Preis": "25", "Menge": "3"]),
        ]
        return database
    }()

    func value(_ formula: String, row: Int = 0) -> Formula.Value {
        Formula.value(of: Field(name: "F", type: .formula, formula: formula), row: database.rows[row], in: database,
                      now: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 31))!)
    }

    @Test func arithmeticAndColumns() {
        #expect(value("[Preis] * [Menge]") == .number(25))
        #expect(value("([Preis] + 2.5) / 3") == .number(5))
        #expect(value("-[Menge] + 1") == .number(-1))
        #expect(value("SUMME([Menge])") == .number(5))
        #expect(value("SUMME([Preis]; [Menge]; 1)") == .number(15.5))
        #expect(value("MITTELWERT([Preis])") == .number(18.75))
        #expect(value("ANZAHL([Bezahlt])") == .number(2))
        #expect(value("MAX([Total])") == .number(75))
        #expect(value("[Anteil]") == .number(25))
        #expect(value("RUNDEN(2.345; 2)") == .number(2.35))
    }

    @Test func textLogicAndDates() {
        #expect(value("[Name] & \" x\" & [Menge]") == .text("Pizza x2"))
        #expect(value("WENN([Bezahlt]; \"ok\"; \"offen\")") == .text("ok"))
        #expect(value("WENN([Bezahlt]; \"ok\"; \"offen\")", row: 1) == .text("offen"))
        #expect(value("IF([Menge] >= 3, \"viel\", \"wenig\")", row: 1) == .text("viel"))
        #expect(value("UND([Menge] > 1; NICHT([Bezahlt]))", row: 1) == .bool(true))
        #expect(value("TAGE([Bis]; [Von])") == .number(10))
        #expect(value("[Bis] - [Von]") == .number(10))
        #expect(value("TAGE(HEUTE(); [Von])") == .number(30))
        #expect(value("JAHR([Von])") == .number(2026))
        #expect(value("ISTLEER([Von])", row: 1) == .bool(true))
    }

    @Test func errors() {
        #expect(value("[Preis] / 0") == .error("Division durch 0"))
        #expect(value("[Name] * 2") == .error("* braucht Zahlen"))
        if case .error = value("FOO(1)") {} else { Issue.record("unbekannte Funktion") }
        #expect(Formula.check("[Preis] * ", fields: database.fields) == "Formel endet zu früh")
        #expect(Formula.check("[Gibts nicht] + 1", fields: database.fields) == "Unbekanntes Feld [Gibts nicht]")
        #expect(Formula.check("SUMME([Preis])", fields: database.fields) == nil)
        let loop = Database(fields: [Field(name: "A", type: .formula, formula: "[A] + 1")], rows: [Row(id: "x")])
        if case .error = Formula.value(of: loop.fields[0], row: loop.rows[0], in: loop) {} else { Issue.record("Schleife") }
    }

    @Test func queryFileAndDisplay() throws {
        var view = SavedView(name: "x")
        view.sorts = [SortRule(field: "Total", descending: true)]
        let result = DatabaseQuery.run(view, on: database)
        #expect(result.rows.map(\.id) == ["b", "a"])
        #expect(result.rows.first?["Total"] == "75")
        #expect(DatabaseQuery.compute(.sum, field: database.fields[6], rows: result.rows) == 100)
        #expect(DatabaseQuery.compute(.average, field: database.fields[6], rows: result.rows) == 50)
        #expect(DatabaseQuery.compute(.max, field: database.fields[6], rows: result.rows) == 75)
        #expect(Aggregate.available(for: .formula) == Aggregate.allCases)
        #expect(CellValue.display("75", for: database.fields[6]).contains("75.00"))
        // In der Datei bleibt die Formel, die Werte nicht.
        let text = DatabaseFile.serialize(Formula.computing(database))
        #expect(text.contains(#""formel":"=[Preis] * [Menge]""#))
        #expect(!text.contains("| 75 |"))
        #expect(try DatabaseFile.parse(text).fields[6].formula == "=[Preis] * [Menge]")
    }
}
