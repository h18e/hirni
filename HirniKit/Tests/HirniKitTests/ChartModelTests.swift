import Foundation
import Testing
@testable import HirniKit

struct ChartModelTests {
    let db = Database(
        fields: [
            Field(name: "Name", type: .text),
            Field(name: "Betrag", type: .number, format: .chf),
            Field(name: "Kategorie", type: .select, options: ["Essen", "Reisen"]),
            Field(name: "Datum", type: .date),
        ],
        rows: [
            Row(id: "1", values: ["Betrag": "40", "Kategorie": "Essen", "Datum": "2026-08-05"]),
            Row(id: "2", values: ["Betrag": "20", "Kategorie": "Reisen", "Datum": "2026-08-20"]),
            Row(id: "3", values: ["Betrag": "10", "Kategorie": "Essen", "Datum": "2026-10-02"]),
            Row(id: "4", values: ["Betrag": "x", "Kategorie": "Essen"]), // ohne Datum
        ]
    )

    @Test func sumPerMonthFillsEmptyMonths() throws {
        let settings = ChartSettings(xField: "Datum", interval: .month, measure: .sum, valueField: "Betrag")
        let data = try #require(ChartModel.data(for: settings, rows: db.rows, in: db))
        #expect(data.labels.count == 3) // August, September (leer), Oktober
        #expect(data.points.map(\.value) == [60, 0, 10])
        #expect(data.labels.first?.contains("Aug") == true)
    }

    @Test func averageSkipsEmptyMonths() throws {
        let settings = ChartSettings(xField: "Datum", interval: .month, measure: .average, valueField: "Betrag")
        let data = try #require(ChartModel.data(for: settings, rows: db.rows, in: db))
        #expect(data.points.map(\.value) == [30, 10])
    }

    @Test func countPerCategoryWithOptionOrder() throws {
        let settings = ChartSettings(xField: "Kategorie", measure: .count)
        let data = try #require(ChartModel.data(for: settings, rows: db.rows, in: db))
        #expect(data.labels == ["Essen", "Reisen"])
        #expect(data.points.map(\.value) == [3, 1])
    }

    @Test func splitIntoSeries() throws {
        let settings = ChartSettings(xField: "Datum", interval: .month, measure: .sum, valueField: "Betrag", splitField: "Kategorie")
        let data = try #require(ChartModel.data(for: settings, rows: db.rows, in: db))
        #expect(data.series == ["Essen", "Reisen"])
        let august = data.points.filter { $0.order == 0 }
        #expect(august.map(\.series) == ["Essen", "Reisen"])
        #expect(august.map(\.value) == [40, 20])
        // Reisen fehlt im September und Oktober: dort 0 statt Lücke
        let reisen = data.points.filter { $0.series == "Reisen" }
        #expect(reisen.map(\.value) == [20, 0, 0])
    }

    @Test func invalidSettingsGiveNoChart() {
        #expect(ChartModel.data(for: ChartSettings(xField: "Gibt es nicht"), rows: db.rows, in: db) == nil)
        #expect(ChartModel.data(for: ChartSettings(xField: "Datum", measure: .sum, valueField: "Name"), rows: db.rows, in: db) == nil)
    }

    @Test func weeksAndYears() throws {
        let weeks = try #require(ChartModel.data(for: ChartSettings(xField: "Datum", interval: .week), rows: db.rows, in: db))
        #expect(weeks.labels.first == "KW 32")
        let years = try #require(ChartModel.data(for: ChartSettings(xField: "Datum", interval: .year), rows: db.rows, in: db))
        #expect(years.labels == ["2026"])
        #expect(years.points.first?.value == 3)
    }

    @Test func defaultsAndFileRoundTrip() throws {
        let defaults = ChartModel.defaultSettings(for: db)
        #expect(defaults.xField == "Datum" && defaults.measure == .sum && defaults.valueField == "Betrag")

        var view = SavedView(name: "Pro Monat", kind: .chart)
        view.chart = defaults
        var copy = db
        copy.views = [view]
        let text = DatabaseFile.serialize(copy)
        #expect(text.contains(#""diagramm":{"#))
        #expect(try DatabaseFile.parse(text).views == [view])

        view.renameField("Betrag", to: nil)
        #expect(view.chart?.valueField == nil && view.chart?.measure == .count)
    }
}
