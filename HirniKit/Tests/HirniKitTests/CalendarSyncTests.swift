import Foundation
import Testing
@testable import HirniKit

struct CalendarSyncTests {
    @Test func calendarFieldRoundTrip() throws {
        var database = Database(fields: [Field(name: "Name", type: .text), Field(name: "Am", type: .date)])
        database.calendarField = "Am"
        let text = DatabaseFile.serialize(database)
        #expect(text.contains("kalender: \"Am\""))
        #expect(try DatabaseFile.parse(text).calendarField == "Am")
        database.calendarField = nil
        #expect(try DatabaseFile.parse(DatabaseFile.serialize(database)).calendarField == nil)
    }

    @Test func itemsFromRows() throws {
        var database = Database(fields: [Field(name: "Name", type: .text), Field(name: "Am", type: .date)])
        database.rows = [
            Row(id: "a", values: ["Name": "Zahnarzt", "Am": "2026-11-03 14:30"]),
            Row(id: "b", values: ["Name": "Ferien", "Am": "2026-12-20/2026-12-27"]),
            Row(id: "c", values: ["Name": "Ohne Datum"]),
        ]
        #expect(CalendarSync.items(of: database, path: "Inbox/T.hirnidb.md", title: "Termine").isEmpty)
        database.calendarField = "Am"
        let items = CalendarSync.items(of: database, path: "Inbox/T.hirnidb.md", title: "Termine")
        #expect(items.map(\.title) == ["Zahnarzt", "Ferien"])
        #expect(!items[0].isAllDay)
        #expect(items[0].end.timeIntervalSince(items[0].start) == 3600)
        #expect(items[1].isAllDay)
        let days = Calendar.current.dateComponents([.day], from: items[1].start, to: items[1].end).day
        #expect(days == 7)
        #expect(items[0].url.absoluteString == "hirni://notiz?pfad=Inbox/T.hirnidb.md&zeile=a")
    }

    @Test func planDiffsByURL() {
        func item(_ id: String, _ title: String) -> CalendarItem {
            CalendarItem(url: URL(string: "hirni://notiz?pfad=x&zeile=\(id)")!, title: title,
                         start: .init(timeIntervalSince1970: 0), end: .init(timeIntervalSince1970: 60), isAllDay: false, notes: "")
        }
        let existing = [
            ExistingCalendarEvent(id: "e1", item: item("a", "A")),
            ExistingCalendarEvent(id: "e2", item: item("b", "B alt")),
            ExistingCalendarEvent(id: "e3", item: item("b", "B alt")), // doppelt
            ExistingCalendarEvent(id: "e4", item: item("z", "Gelöscht")),
            ExistingCalendarEvent(id: "e5", item: nil),
        ]
        let plan = CalendarSync.plan(existing: existing, wanted: [item("a", "A"), item("b", "B"), item("c", "C")])
        #expect(plan.create == [item("c", "C")])
        #expect(plan.update.map(\.id) == ["e2"])
        #expect(plan.update.first?.item.title == "B")
        #expect(plan.delete == ["e3", "e4", "e5"])
    }
}
