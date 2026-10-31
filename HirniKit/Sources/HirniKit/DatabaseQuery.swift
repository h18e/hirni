import Foundation

/// Das Ergebnis einer Ansicht: gefilterte, sortierte und gruppierte Zeilen.
public struct QueryResult: Equatable, Sendable {
    public struct Group: Identifiable, Equatable, Sendable {
        public let id: String
        /// `nil`, wenn nicht gruppiert wird.
        public let title: String?
        public let rows: [Row]

        public init(id: String, title: String?, rows: [Row]) {
            self.id = id
            self.title = title
            self.rows = rows
        }
    }

    public let groups: [Group]
    /// Alle sichtbaren Zeilen, ohne Doppelte (bei Mehrfachauswahl kann eine
    /// Zeile in mehreren Gruppen stehen).
    public let rows: [Row]
}

/// Wendet eine Ansicht auf eine Datenbank an.
public enum DatabaseQuery {
    /// `alwaysShowing`: eben angelegte Zeilen bleiben sichtbar, auch wenn sie
    /// den Filter (noch) nicht erfüllen. Sonst verschwände ein neuer Eintrag
    /// sofort wieder.
    public static func run(_ view: SavedView?, on database: Database, alwaysShowing: Set<String> = []) -> QueryResult {
        let database = Formula.computing(database)
        var rows = database.rows.filter { row in
            alwaysShowing.contains(row.id) || (view?.filters ?? []).allSatisfy { rule in
                guard let field = database.field(named: rule.field) else { return true }
                return matches(row[field.name], rule, field)
            }
        }

        let sorts = (view?.sorts ?? []).compactMap { rule in database.field(named: rule.field).map { (rule, $0) } }
        if !sorts.isEmpty {
            // Stabil sortieren: Bei Gleichstand bleibt die Reihenfolge der Datei.
            let indexed = rows.enumerated().map { ($0.offset, $0.element) }
            rows = indexed.sorted { a, b in
                for (rule, field) in sorts {
                    let result = compare(a.1[field.name], b.1[field.name], field, descending: rule.descending)
                    if result != .orderedSame { return result == .orderedAscending }
                }
                return a.0 < b.0
            }.map(\.1)
        }

        guard let name = view?.groupBy, let field = database.field(named: name) else {
            return QueryResult(groups: [.init(id: "alle", title: nil, rows: rows)], rows: rows)
        }
        return QueryResult(groups: group(rows, by: field), rows: rows)
    }

    // MARK: - Filter

    static func matches(_ raw: String, _ rule: FilterRule, _ field: Field) -> Bool {
        let value = rule.value ?? ""
        switch rule.condition {
        case .isEmpty: return raw.trimmingCharacters(in: .whitespaces).isEmpty
        case .isNotEmpty: return !raw.trimmingCharacters(in: .whitespaces).isEmpty
        case .checked: return CellValue.bool(raw)
        case .unchecked: return !CellValue.bool(raw)
        default: break
        }
        // Ohne Vergleichswert schränkt eine Regel noch nichts ein.
        guard !value.isEmpty else { return true }

        switch field.type {
        case .number:
            guard let a = CellValue.number(raw), let b = CellValue.number(value) else { return rule.condition == .notEquals }
            switch rule.condition {
            case .equals: return a == b
            case .notEquals: return a != b
            case .greater: return a > b
            case .less: return a < b
            case .greaterOrEqual: return a >= b
            case .lessOrEqual: return a <= b
            default: return true
            }
        case .date:
            guard let a = CellValue.date(raw)?.start, let b = CellValue.date(value)?.start else { return false }
            let calendar = Calendar.current
            switch rule.condition {
            case .equals: return calendar.isDate(a, inSameDayAs: b)
            case .before: return calendar.startOfDay(for: a) < calendar.startOfDay(for: b)
            case .after: return calendar.startOfDay(for: a) > calendar.startOfDay(for: b)
            default: return true
            }
        case .multiSelect:
            let list = CellValue.list(raw).map { $0.lowercased() }
            switch rule.condition {
            case .contains: return list.contains(value.lowercased())
            case .notContains: return !list.contains(value.lowercased())
            default: return true
            }
        case .formula:
            // Zahlen als Zahlen vergleichen, sonst als Text.
            if let a = CellValue.number(raw), let b = CellValue.number(value), CellValue.date(raw) == nil {
                switch rule.condition {
                case .equals: return a == b
                case .notEquals: return a != b
                case .greater: return a > b
                case .less: return a < b
                case .greaterOrEqual: return a >= b
                case .lessOrEqual: return a <= b
                default: break
                }
            }
            let a = raw.lowercased(), b = value.lowercased()
            switch rule.condition {
            case .equals: return a == b
            case .notEquals: return a != b
            case .contains: return a.contains(b)
            case .notContains: return !a.contains(b)
            default: return true
            }
        case .text, .url, .select, .checkbox:
            let a = raw.lowercased(), b = value.lowercased()
            switch rule.condition {
            case .equals: return a == b
            case .notEquals: return a != b
            case .contains: return a.contains(b)
            case .notContains: return !a.contains(b)
            default: return true
            }
        }
    }

    // MARK: - Sortieren

    /// Leere Werte stehen immer am Ende, auch beim absteigenden Sortieren.
    static func compare(_ a: String, _ b: String, _ field: Field, descending: Bool) -> ComparisonResult {
        let aEmpty = a.trimmingCharacters(in: .whitespaces).isEmpty
        let bEmpty = b.trimmingCharacters(in: .whitespaces).isEmpty
        if aEmpty || bEmpty {
            return aEmpty == bEmpty ? .orderedSame : (aEmpty ? .orderedDescending : .orderedAscending)
        }
        let result: ComparisonResult
        switch field.type {
        case .number:
            result = compareValues(CellValue.number(a), CellValue.number(b)) ?? a.localizedStandardCompare(b)
        case .date:
            result = compareValues(CellValue.date(a)?.start, CellValue.date(b)?.start) ?? a.compare(b)
        case .checkbox:
            result = compareValues(CellValue.bool(a) ? 1 : 0, CellValue.bool(b) ? 1 : 0) ?? .orderedSame
        case .select:
            // Reihenfolge wie in den Optionen, wie bei Notion.
            let options = field.options ?? []
            result = compareValues(options.firstIndex(of: a) ?? .max, options.firstIndex(of: b) ?? .max)
                ?? a.localizedStandardCompare(b)
        case .text, .url, .multiSelect:
            result = a.localizedStandardCompare(b)
        case .formula:
            result = compareValues(CellValue.date(a)?.start, CellValue.date(b)?.start)
                ?? compareValues(CellValue.number(a), CellValue.number(b))
                ?? a.localizedStandardCompare(b)
        }
        guard descending else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    private static func compareValues<T: Comparable>(_ a: T?, _ b: T?) -> ComparisonResult? {
        guard let a, let b else { return nil }
        return a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }

    // MARK: - Gruppieren

    /// Felder, nach denen sich gruppieren lässt.
    public static func canGroup(by field: Field) -> Bool {
        field.type != .url
    }

    static func group(_ rows: [Row], by field: Field) -> [QueryResult.Group] {
        var keys: [String] = []
        var buckets: [String: [Row]] = [:]
        var titles: [String: String] = [:]
        let emptyKey = "\u{0}leer"

        func add(_ row: Row, key: String, title: String) {
            if buckets[key] == nil { keys.append(key) }
            buckets[key, default: []].append(row)
            titles[key] = title
        }

        for row in rows {
            let raw = row[field.name]
            switch field.type {
            case .multiSelect:
                let values = CellValue.list(raw)
                if values.isEmpty { add(row, key: emptyKey, title: "Ohne \(field.name)") }
                for value in values { add(row, key: value, title: value) }
            case .checkbox:
                let checked = CellValue.bool(raw)
                add(row, key: checked ? "1" : "0", title: checked ? "Angehakt" : "Nicht angehakt")
            case .date:
                if let date = CellValue.date(raw)?.start {
                    let month = Calendar.current.dateComponents([.year, .month], from: date)
                    let key = String(format: "%04d-%02d", month.year ?? 0, month.month ?? 0)
                    add(row, key: key, title: date.formatted(.dateTime.locale(Locale(identifier: "de_CH")).month(.wide).year()))
                } else {
                    add(row, key: emptyKey, title: "Ohne \(field.name)")
                }
            default:
                let value = raw.trimmingCharacters(in: .whitespaces)
                value.isEmpty ? add(row, key: emptyKey, title: "Ohne \(field.name)") : add(row, key: value, title: CellValue.display(value, for: field))
            }
        }

        let options = field.options ?? []
        let sorted = keys.sorted { a, b in
            if a == emptyKey || b == emptyKey { return b == emptyKey && a != emptyKey }
            switch field.type {
            case .select, .multiSelect:
                return (options.firstIndex(of: a) ?? .max, a) < (options.firstIndex(of: b) ?? .max, b)
            case .checkbox:
                return a > b // angehakt zuerst
            case .number:
                return (CellValue.number(a) ?? 0) < (CellValue.number(b) ?? 0)
            default:
                return a.localizedStandardCompare(b) == .orderedAscending // Datum: «2026-03» vor «2026-10»
            }
        }
        return sorted.map { QueryResult.Group(id: $0, title: titles[$0], rows: buckets[$0] ?? []) }
    }

    // MARK: - Berechnen

    /// Ergebnis als Zahl (`nil`, wenn nichts zu berechnen ist).
    public static func compute(_ aggregate: Aggregate, field: Field, rows: [Row]) -> Double? {
        let raws = rows.map { $0[field.name] }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if aggregate == .count {
            return Double(field.type == .checkbox ? raws.filter(CellValue.bool).count : raws.count)
        }
        let numbers = raws.compactMap(CellValue.number)
        guard !numbers.isEmpty else { return nil }
        switch aggregate {
        case .count: return Double(numbers.count)
        case .sum: return numbers.reduce(0, +)
        case .average: return numbers.reduce(0, +) / Double(numbers.count)
        case .min: return numbers.min()
        case .max: return numbers.max()
        }
    }

    /// Ergebnis zum Anzeigen, z. B. «CHF 60.50» oder «12».
    public static func display(_ aggregate: Aggregate, field: Field, rows: [Row]) -> String {
        guard let value = compute(aggregate, field: field, rows: rows) else { return "–" }
        if aggregate == .count { return value.formatted(.number.locale(Locale(identifier: "de_CH"))) }
        return CellValue.display(number: value, format: field.format)
    }
}
