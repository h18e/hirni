import Foundation

/// Ein Wert im Diagramm: eine Säule bzw. ein Punkt der Linie.
public struct ChartPoint: Identifiable, Equatable, Sendable {
    public var id: String { "\(order)|\(series ?? "")" }
    /// Beschriftung auf der waagrechten Achse, z. B. «Okt. 2026» oder «Essen».
    public let label: String
    /// Reihenfolge auf der Achse.
    public let order: Int
    /// Teilreihe (aufgeteilt nach), `nil` ohne Aufteilen.
    public let series: String?
    public let value: Double
}

public struct ChartData: Equatable, Sendable {
    public let points: [ChartPoint]
    /// Achsen-Beschriftungen in der richtigen Reihenfolge.
    public let labels: [String]
    /// Teilreihen in der richtigen Reihenfolge (für Farben und Legende).
    public let series: [String]
}

/// Rechnet die Daten für eine Diagramm-Ansicht aus den sichtbaren Zeilen.
public enum ChartModel {
    /// Längste Achse bei Datumswerten. Mehr Säulen wären ohnehin unlesbar.
    static let maxBuckets = 400

    public static func data(for settings: ChartSettings, rows: [Row], in database: Database) -> ChartData? {
        guard let xField = settings.xField.flatMap(database.field(named:)) else { return nil }
        let valueField = settings.valueField.flatMap(database.field(named:))
        if settings.measure != .count, valueField?.type.isNumeric != true { return nil }
        let splitField = settings.splitField.flatMap(database.field(named:))

        // 1. Zeilen auf die Achse verteilen
        var buckets: [(key: String, label: String, rows: [Row])]
        if xField.type == .date {
            buckets = dateBuckets(rows, field: xField, interval: settings.interval,
                                  fillGaps: settings.measure != .average)
        } else {
            buckets = DatabaseQuery.group(rows, by: xField).map { ($0.id, $0.title ?? "", $0.rows) }
        }

        // 2. Pro Achsenwert und Teilreihe messen
        var seriesOrder: [String] = []
        var points: [ChartPoint] = []
        for (index, bucket) in buckets.enumerated() {
            if let splitField {
                let groups = DatabaseQuery.group(bucket.rows, by: splitField)
                for group in groups {
                    let name = group.title ?? ""
                    if !seriesOrder.contains(name) { seriesOrder.append(name) }
                    if let value = measure(settings.measure, valueField, group.rows) {
                        points.append(ChartPoint(label: bucket.label, order: index, series: name, value: value))
                    }
                }
            } else if let value = measure(settings.measure, valueField, bucket.rows) ?? (bucket.rows.isEmpty ? 0 : nil) {
                points.append(ChartPoint(label: bucket.label, order: index, series: nil, value: value))
            }
        }

        // Teilreihen in der Reihenfolge der Optionen, «Ohne …» zuletzt.
        if let options = splitField?.options {
            seriesOrder.sort { (options.firstIndex(of: $0) ?? .max) < (options.firstIndex(of: $1) ?? .max) }
        }

        // Fehlt eine Teilreihe in einem Abschnitt, zählt sie dort 0 – sonst
        // zöge die Linie über die Lücke hinweg. Durchschnitte bleiben leer.
        if splitField != nil, settings.measure != .average {
            let present = Set(points.map(\.id))
            for (index, bucket) in buckets.enumerated() {
                for name in seriesOrder where !present.contains("\(index)|\(name)") {
                    points.append(ChartPoint(label: bucket.label, order: index, series: name, value: 0))
                }
            }
        }
        points.sort { ($0.order, seriesOrder.firstIndex(of: $0.series ?? "") ?? 0) < ($1.order, seriesOrder.firstIndex(of: $1.series ?? "") ?? 0) }
        return ChartData(points: points, labels: buckets.map(\.label), series: seriesOrder)
    }

    private static func measure(_ measure: ChartSettings.ChartMeasure, _ field: Field?, _ rows: [Row]) -> Double? {
        switch measure {
        case .count:
            return Double(rows.count)
        case .sum:
            guard let field else { return nil }
            return DatabaseQuery.compute(.sum, field: field, rows: rows) ?? 0
        case .average:
            guard let field else { return nil }
            return DatabaseQuery.compute(.average, field: field, rows: rows)
        }
    }

    /// Zeilen nach Tag/Woche/Monat/Jahr. Mit `fillGaps` erscheinen auch leere
    /// Zeitabschnitte dazwischen (für Anzahl und Summe sinnvoll, nicht für
    /// Durchschnitte).
    static func dateBuckets(_ rows: [Row], field: Field, interval: ChartSettings.DateInterval, fillGaps: Bool)
        -> [(key: String, label: String, rows: [Row])] {
        let calendar = CalendarModel.calendar
        let component: Calendar.Component = switch interval {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }

        var byStart: [Date: [Row]] = [:]
        for row in rows {
            guard let date = CellValue.date(row[field.name])?.start,
                  let start = calendar.dateInterval(of: component, for: date)?.start
            else { continue }
            byStart[start, default: []].append(row)
        }
        guard let first = byStart.keys.min(), let last = byStart.keys.max() else { return [] }

        var starts: [Date]
        if fillGaps {
            starts = []
            var current = first
            while current <= last, starts.count < maxBuckets {
                starts.append(current)
                guard let next = calendar.date(byAdding: component, value: 1, to: current) else { break }
                current = next
            }
        } else {
            starts = byStart.keys.sorted()
        }

        return starts.map { start in
            (key: ISO8601DateFormatter().string(from: start), label: label(for: start, interval: interval), rows: byStart[start] ?? [])
        }
    }

    static func label(for date: Date, interval: ChartSettings.DateInterval) -> String {
        let locale = Locale(identifier: "de_CH")
        switch interval {
        case .day:
            return date.formatted(.dateTime.locale(locale).day().month(.abbreviated))
        case .week:
            let week = CalendarModel.calendar.component(.weekOfYear, from: date)
            return "KW \(week)"
        case .month:
            return date.formatted(.dateTime.locale(locale).month(.abbreviated).year(.twoDigits))
        case .year:
            return date.formatted(.dateTime.locale(locale).year())
        }
    }

    /// Vorschlag für eine neue Diagramm-Ansicht: Datum nach Monat, Summe des
    /// ersten Zahlenfelds (sonst Anzahl).
    public static func defaultSettings(for database: Database) -> ChartSettings {
        let x = database.fields.first { $0.type == .date } ?? database.fields.first { $0.type == .select } ?? database.fields.first
        let number = database.fields.first { $0.type == .number }
        return ChartSettings(
            style: .bar,
            xField: x?.name,
            interval: .month,
            measure: number == nil ? .count : .sum,
            valueField: number?.name
        )
    }
}
