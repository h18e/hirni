import Foundation

/// Ein Termin für den Apple Kalender «Hirni»: ein Eintrag einer Datenbank mit
/// eingeschaltetem Kalender (`Database.calendarField`).
public struct CalendarItem: Equatable, Sendable {
    /// Link zurück zum Eintrag; dient zugleich als Kennung des Termins.
    public var url: URL
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var notes: String

    public init(url: URL, title: String, start: Date, end: Date, isAllDay: Bool, notes: String) {
        self.url = url
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.notes = notes
    }
}

/// Ein Termin, der schon im Kalender «Hirni» steht.
public struct ExistingCalendarEvent: Equatable, Sendable {
    public var id: String
    public var item: CalendarItem?

    /// `item` = `nil`: Termin ohne Hirni-Link (von Hand angelegt) → wird entfernt.
    public init(id: String, item: CalendarItem?) {
        self.id = id
        self.item = item
    }
}

public enum CalendarSync {
    /// Was im Kalender zu tun ist, damit er genau `wanted` zeigt.
    public struct Plan: Equatable, Sendable {
        public var create: [CalendarItem] = []
        public var update: [(id: String, item: CalendarItem)] = []
        public var delete: [String] = []

        public var isEmpty: Bool { create.isEmpty && update.isEmpty && delete.isEmpty }

        public static func == (a: Plan, b: Plan) -> Bool {
            a.create == b.create && a.delete == b.delete
                && a.update.map(\.id) == b.update.map(\.id) && a.update.map(\.item) == b.update.map(\.item)
        }
    }

    /// Alle Termine aus den Datenbanken mit eingeschaltetem Kalender.
    public static func items(in vault: Vault) -> [CalendarItem] {
        vault.allDatabaseURLs().flatMap { url -> [CalendarItem] in
            guard let database = try? vault.readDatabase(at: url) else { return [] }
            return items(of: database, path: vault.relativePath(of: url) ?? url.lastPathComponent, title: Vault.title(of: url))
        }
    }

    static func items(of database: Database, path: String, title databaseTitle: String) -> [CalendarItem] {
        guard let name = database.calendarField, let dateField = database.field(named: name), dateField.type == .date
        else { return [] }
        let titleField = database.fields.first { $0.name != name }
        let calendar = Calendar.current
        return database.rows.compactMap { row in
            guard let date = CellValue.date(row[name]) else { return nil }
            let title = titleField.map { CellValue.display(row[$0.name], for: $0) } ?? ""
            let start: Date
            let end: Date
            if date.includesTime {
                start = date.start
                end = max(date.end ?? date.start.addingTimeInterval(3600), date.start)
            } else {
                // Ganztägig: bis zum Ende des letzten Tags.
                start = calendar.startOfDay(for: date.start)
                let lastDay = calendar.startOfDay(for: max(date.end ?? date.start, date.start))
                end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: lastDay) ?? lastDay
            }
            var parts = URLComponents()
            parts.scheme = "hirni"
            parts.host = "notiz"
            parts.queryItems = [URLQueryItem(name: "pfad", value: path), URLQueryItem(name: "zeile", value: row.id)]
            guard let url = parts.url else { return nil }
            return CalendarItem(
                url: url,
                title: title.isEmpty ? databaseTitle : title,
                start: start, end: end, isAllDay: !date.includesTime,
                notes: "Aus der Hirni-Datenbank «\(databaseTitle)». Änderungen bitte in Hirni machen, hier werden sie überschrieben."
            )
        }
    }

    /// Vergleicht nach Link: Neue anlegen, Geänderte nachführen, Überzählige
    /// (gelöschte Einträge, Doppelte, fremde Termine) entfernen.
    public static func plan(existing: [ExistingCalendarEvent], wanted: [CalendarItem]) -> Plan {
        var plan = Plan()
        var wantedByURL: [URL: CalendarItem] = [:]
        for item in wanted where wantedByURL[item.url] == nil { wantedByURL[item.url] = item }
        var seen = Set<URL>()
        for event in existing {
            guard let current = event.item, let target = wantedByURL[current.url], seen.insert(current.url).inserted else {
                plan.delete.append(event.id)
                continue
            }
            if current != target { plan.update.append((event.id, target)) }
        }
        var created = Set<URL>()
        for item in wanted where !seen.contains(item.url) && created.insert(item.url).inserted {
            plan.create.append(item)
        }
        return plan
    }
}
