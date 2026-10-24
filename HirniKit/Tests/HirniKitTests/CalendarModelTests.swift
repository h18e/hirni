import Foundation
import Testing
@testable import HirniKit

struct CalendarModelTests {
    private func day(_ text: String) -> Date {
        CalendarModel.calendar.startOfDay(for: CellValue.date(text)!.start)
    }

    @Test func octoberStartsOnMondayInSeptember() {
        let weeks = CalendarModel.weeks(ofMonthContaining: day("2026-10-15"))
        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks.first?.first == day("2026-09-28"))   // Montag
        #expect(weeks.last?.last == day("2026-11-01"))     // Sonntag
        #expect(weeks.joined().contains(day("2026-10-31")))
    }

    @Test func entriesIncludingRangesAcrossMonthEnd() {
        let date = Field(name: "Datum", type: .date)
        let rows = [
            Row(id: "a", values: ["Datum": "2026-10-24"]),
            Row(id: "b", values: ["Datum": "2026-10-30/2026-11-02"]), // Zeitraum über das Monatsende
            Row(id: "c", values: ["Datum": "kein Datum"]),
            Row(id: "d", values: ["Datum": "2026-10-24 18:00"]),
        ]
        let entries = CalendarModel.entries(rows, dateField: date, from: day("2026-10-01"), to: day("2026-10-31"))
        #expect(entries[day("2026-10-24")]?.map(\.id) == ["a", "d"])
        #expect(entries[day("2026-10-30")]?.map(\.id) == ["b"])
        #expect(entries[day("2026-10-31")]?.map(\.id) == ["b"])
        #expect(entries[day("2026-11-01")] == nil) // ausserhalb des Bereichs
        #expect(entries.values.joined().contains { $0.id == "c" } == false)
    }

    @Test func colorsFollowOptionOrder() {
        let parent = Field(name: "Bei", type: .select, options: ["Mama", "Papa"])
        #expect(CalendarModel.colorIndex(of: Row(values: ["Bei": "Papa"]), colorField: parent) == 1)
        #expect(CalendarModel.colorIndex(of: Row(values: [:]), colorField: parent) == nil)
        #expect(CalendarModel.colorIndex(of: Row(values: ["Bei": "Mama"]), colorField: nil) == nil)
    }

    @Test func weekendsAndDefaultDateField() {
        #expect(CalendarModel.isWeekend(day("2026-10-24")))  // Samstag
        #expect(!CalendarModel.isWeekend(day("2026-10-23")))
        let db = Database(fields: [Field(name: "Name", type: .text), Field(name: "Wann", type: .date)])
        #expect(CalendarModel.dateField(for: SavedView(name: "K", kind: .calendar), in: db)?.name == "Wann")
    }

    @Test func calendarSettingsRoundTripAndFollowRenames() throws {
        var view = SavedView(name: "Weekends", kind: .calendar)
        view.dateField = "Wann"
        view.colorField = "Bei"
        var db = Database(fields: [Field(name: "Wann", type: .date), Field(name: "Bei", type: .select, options: ["Mama"])])
        db.views = [view]
        let back = try DatabaseFile.parse(DatabaseFile.serialize(db))
        #expect(back.views == [view])

        view.renameField("Bei", to: "Kinder bei")
        #expect(view.colorField == "Kinder bei")
        view.renameField("Wann", to: nil)
        #expect(view.dateField == nil)
    }
}
