import Foundation

/// Rechnet für die Kalender-Ansicht: Monatsraster und Einträge pro Tag.
public enum CalendarModel {
    /// Gregorianischer Kalender wie in der Schweiz: Woche beginnt am Montag.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_CH")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = .current
        return calendar
    }

    /// Längster Zeitraum, der Tag für Tag eingetragen wird. Schützt vor
    /// Tippfehlern wie «2026–2062».
    static let maxRangeDays = 366

    /// Wochen des Monats, der `date` enthält: je 7 Tage, Montag zuerst,
    /// ergänzt um die Tage der Nachbarmonate. Jeder Tag als Tagesbeginn.
    public static func weeks(ofMonthContaining date: Date) -> [[Date]] {
        let calendar = calendar
        guard let month = calendar.dateInterval(of: .month, for: date),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start)
        else { return [] }
        let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end) ?? month.start
        var weeks: [[Date]] = []
        var day = firstWeek.start
        while day <= lastDay {
            var week: [Date] = []
            for _ in 0..<7 {
                week.append(day)
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
            weeks.append(week)
        }
        return weeks
    }

    /// Einträge pro Tag zwischen `start` und `end` (beide eingeschlossen).
    /// Ein Zeitraum erscheint an jedem seiner Tage.
    public static func entries(_ rows: [Row], dateField: Field, from start: Date, to end: Date) -> [Date: [Row]] {
        let calendar = calendar
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        var result: [Date: [Row]] = [:]
        for row in rows {
            guard let value = CellValue.date(row[dateField.name]) else { continue }
            var day = calendar.startOfDay(for: value.start)
            let rangeEnd = calendar.startOfDay(for: max(value.end ?? value.start, value.start))
            var count = 0
            while day <= rangeEnd, count < maxRangeDays {
                if day >= first, day <= last { result[day, default: []].append(row) }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                count += 1
            }
        }
        return result
    }

    /// Position der Option im Farbfeld, für eine gleichbleibende Farbe pro Option.
    public static func colorIndex(of row: Row, colorField: Field?) -> Int? {
        guard let colorField else { return nil }
        let value = colorField.type == .multiSelect ? CellValue.list(row[colorField.name]).first ?? "" : row[colorField.name]
        guard !value.isEmpty else { return nil }
        // Werte ausserhalb der Optionen: feste Zahl aus den Zeichen (nicht
        // `hashValue`, das sich bei jedem Start ändert).
        return colorField.options?.firstIndex(of: value) ?? value.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    }

    public static func isWeekend(_ date: Date) -> Bool {
        calendar.isDateInWeekend(date)
    }

    /// Kalender-Felder einer Ansicht: das gewählte Datumsfeld oder das erste.
    public static func dateField(for view: SavedView, in database: Database) -> Field? {
        view.dateField.flatMap(database.field(named:)) ?? database.fields.first { $0.type == .date }
    }
}
