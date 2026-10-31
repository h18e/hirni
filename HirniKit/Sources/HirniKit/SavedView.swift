import Foundation

/// Eine gespeicherte Ansicht einer Datenbank: welche Einträge in welcher
/// Reihenfolge, gruppiert nach was, mit welchen Berechnungen.
///
/// Steht im Kopf der Datei unter `ansichten:`, eine JSON-Zeile pro Ansicht:
///
/// ```
/// ansichten:
///   - {"name": "Ferien", "typ": "tabelle", "filter": [{"feld": "Tags", "bedingung": "enthält", "wert": "Ferien"}],
///      "sortierung": [{"feld": "Datum", "absteigend": true}], "gruppierung": "Kategorie",
///      "berechnungen": {"Betrag": "summe"}, "ausgeblendet": ["Notiz"]}
/// ```
public struct SavedView: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var kind: ViewKind
    public var filters: [FilterRule]?
    public var sorts: [SortRule]?
    public var groupBy: String?
    public var aggregates: [String: Aggregate]?
    public var hiddenFields: [String]?
    /// Kalender: nach welchem Datumsfeld die Einträge verteilt werden.
    public var dateField: String?
    /// Kalender: Einträge farbig nach diesem Auswahlfeld.
    public var colorField: String?
    /// Diagramm: Achsen und Darstellung.
    public var chart: ChartSettings?

    public init(name: String, kind: ViewKind = .table) {
        self.name = name
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey {
        case name
        case kind = "typ"
        case filters = "filter"
        case sorts = "sortierung"
        case groupBy = "gruppierung"
        case aggregates = "berechnungen"
        case hiddenFields = "ausgeblendet"
        case dateField = "datumsfeld"
        case colorField = "farbfeld"
        case chart = "diagramm"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        kind = (try? container.decode(ViewKind.self, forKey: .kind)) ?? .table
        filters = try container.decodeIfPresent([FilterRule].self, forKey: .filters)
        sorts = try container.decodeIfPresent([SortRule].self, forKey: .sorts)
        groupBy = try container.decodeIfPresent(String.self, forKey: .groupBy)
        aggregates = try container.decodeIfPresent([String: Aggregate].self, forKey: .aggregates)
        hiddenFields = try container.decodeIfPresent([String].self, forKey: .hiddenFields)
        dateField = try container.decodeIfPresent(String.self, forKey: .dateField)
        colorField = try container.decodeIfPresent(String.self, forKey: .colorField)
        chart = try? container.decodeIfPresent(ChartSettings.self, forKey: .chart)
    }

    /// Leere Listen nicht schreiben, damit die Datei kurz bleibt.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        if let filters, !filters.isEmpty { try container.encode(filters, forKey: .filters) }
        if let sorts, !sorts.isEmpty { try container.encode(sorts, forKey: .sorts) }
        try container.encodeIfPresent(groupBy, forKey: .groupBy)
        if let aggregates, !aggregates.isEmpty { try container.encode(aggregates, forKey: .aggregates) }
        if let hiddenFields, !hiddenFields.isEmpty { try container.encode(hiddenFields, forKey: .hiddenFields) }
        try container.encodeIfPresent(dateField, forKey: .dateField)
        try container.encodeIfPresent(colorField, forKey: .colorField)
        try container.encodeIfPresent(chart, forKey: .chart)
    }

    /// Filterwerte anpassen, wenn Optionen eines Felds umbenannt wurden.
    public mutating func renameOptions(of field: String, _ renames: [String: String]) {
        guard !renames.isEmpty else { return }
        filters = filters?.map { rule in
            guard rule.field == field, let value = rule.value, let new = renames[value] else { return rule }
            var rule = rule
            rule.value = new
            return rule
        }
    }

    /// Feldnamen in Regeln anpassen, wenn ein Feld umbenannt oder gelöscht wurde.
    public mutating func renameField(_ old: String, to new: String?) {
        filters = filters?.compactMap { rule in
            guard rule.field == old else { return rule }
            guard let new else { return nil }
            var rule = rule
            rule.field = new
            return rule
        }
        sorts = sorts?.compactMap { rule in
            guard rule.field == old else { return rule }
            guard let new else { return nil }
            return SortRule(field: new, descending: rule.descending)
        }
        if groupBy == old { groupBy = new }
        if dateField == old { dateField = new }
        if colorField == old { colorField = new }
        if chart?.xField == old { chart?.xField = new }
        if chart?.valueField == old {
            chart?.valueField = new
            if new == nil { chart?.measure = .count }
        }
        if chart?.splitField == old { chart?.splitField = new }
        if let value = aggregates?.removeValue(forKey: old), let new { aggregates?[new] = value }
        hiddenFields = hiddenFields?.compactMap { $0 == old ? new : $0 }
    }
}

public enum ViewKind: String, Codable, CaseIterable, Sendable {
    case table = "tabelle"
    /// Kurz: pro Eintrag eine Zeile mit Titel und den nächsten Werten.
    case list = "liste"
    case calendar = "kalender"
    case chart = "diagramm"

    public var label: String {
        switch self {
        case .table: "Tabelle"
        case .list: "Liste"
        case .calendar: "Kalender"
        case .chart: "Diagramm"
        }
    }

    public var systemImage: String {
        switch self {
        case .table: "tablecells"
        case .list: "list.bullet"
        case .calendar: "calendar"
        case .chart: "chart.bar"
        }
    }
}

public struct FilterRule: Codable, Equatable, Hashable, Sendable {
    public var field: String
    public var condition: FilterCondition
    /// Rohwert wie in der Tabelle (Zahl `42.5`, Datum `2026-10-24`, Option).
    public var value: String?

    public init(field: String, condition: FilterCondition, value: String? = nil) {
        self.field = field
        self.condition = condition
        self.value = value
    }

    enum CodingKeys: String, CodingKey {
        case field = "feld"
        case condition = "bedingung"
        case value = "wert"
    }
}

public enum FilterCondition: String, Codable, CaseIterable, Sendable {
    case equals = "ist"
    case notEquals = "ist nicht"
    case contains = "enthält"
    case notContains = "enthält nicht"
    case isEmpty = "ist leer"
    case isNotEmpty = "ist nicht leer"
    case greater = ">"
    case less = "<"
    case greaterOrEqual = "≥"
    case lessOrEqual = "≤"
    case before = "vor"
    case after = "nach"
    case checked = "angehakt"
    case unchecked = "nicht angehakt"

    public var label: String {
        switch self {
        case .greater: "grösser als"
        case .less: "kleiner als"
        case .greaterOrEqual: "mindestens"
        case .lessOrEqual: "höchstens"
        default: rawValue
        }
    }

    /// Braucht die Bedingung einen Vergleichswert?
    public var needsValue: Bool {
        ![.isEmpty, .isNotEmpty, .checked, .unchecked].contains(self)
    }

    public static func available(for type: FieldType) -> [FilterCondition] {
        switch type {
        case .text, .url: [.contains, .notContains, .equals, .notEquals, .isEmpty, .isNotEmpty]
        case .number: [.equals, .notEquals, .greater, .less, .greaterOrEqual, .lessOrEqual, .isEmpty, .isNotEmpty]
        case .select: [.equals, .notEquals, .isEmpty, .isNotEmpty]
        case .multiSelect: [.contains, .notContains, .isEmpty, .isNotEmpty]
        case .date: [.equals, .before, .after, .isEmpty, .isNotEmpty]
        case .checkbox: [.checked, .unchecked]
        case .formula: [.equals, .notEquals, .greater, .less, .greaterOrEqual, .lessOrEqual, .contains, .isEmpty, .isNotEmpty]
        }
    }
}

public struct SortRule: Codable, Equatable, Hashable, Sendable {
    public var field: String
    public var descending: Bool

    public init(field: String, descending: Bool = false) {
        self.field = field
        self.descending = descending
    }

    enum CodingKeys: String, CodingKey {
        case field = "feld"
        case descending = "absteigend"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        field = try container.decode(String.self, forKey: .field)
        descending = (try? container.decode(Bool.self, forKey: .descending)) ?? false
    }
}

public enum Aggregate: String, Codable, CaseIterable, Sendable {
    case count = "anzahl"
    case sum = "summe"
    case average = "durchschnitt"
    case min
    case max

    public var label: String {
        switch self {
        case .count: "Anzahl"
        case .sum: "Summe"
        case .average: "Durchschnitt"
        case .min: "Minimum"
        case .max: "Maximum"
        }
    }

    public static func available(for type: FieldType) -> [Aggregate] {
        type == .number ? allCases : [.count]
    }
}

/// Einstellungen einer Diagramm-Ansicht.
///
/// In der Datei: `"diagramm": {"art": "balken", "x": "Datum", "zeitraster": "monat",
/// "y": "summe", "wert": "Betrag", "aufteilen": "Kategorie"}`
public struct ChartSettings: Codable, Equatable, Hashable, Sendable {
    public var style: ChartStyle
    /// Feld für die waagrechte Achse.
    public var xField: String?
    /// Bei einem Datumsfeld: wie fein die Achse ist.
    public var interval: DateInterval
    /// Was die Höhe bestimmt.
    public var measure: ChartMeasure
    /// Zahlenfeld für Summe/Durchschnitt.
    public var valueField: String?
    /// Balken bzw. Linien aufteilen nach diesem Feld (z. B. Kategorie).
    public var splitField: String?

    public init(style: ChartStyle = .bar, xField: String? = nil, interval: DateInterval = .month,
                measure: ChartMeasure = .count, valueField: String? = nil, splitField: String? = nil) {
        self.style = style
        self.xField = xField
        self.interval = interval
        self.measure = measure
        self.valueField = valueField
        self.splitField = splitField
    }

    enum CodingKeys: String, CodingKey {
        case style = "art"
        case xField = "x"
        case interval = "zeitraster"
        case measure = "y"
        case valueField = "wert"
        case splitField = "aufteilen"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = (try? container.decode(ChartStyle.self, forKey: .style)) ?? .bar
        xField = try? container.decodeIfPresent(String.self, forKey: .xField)
        interval = (try? container.decode(DateInterval.self, forKey: .interval)) ?? .month
        measure = (try? container.decode(ChartMeasure.self, forKey: .measure)) ?? .count
        valueField = try? container.decodeIfPresent(String.self, forKey: .valueField)
        splitField = try? container.decodeIfPresent(String.self, forKey: .splitField)
    }

    public enum ChartStyle: String, Codable, CaseIterable, Sendable {
        case bar = "balken"
        case line = "linie"

        public var label: String { self == .bar ? "Balken" : "Linie" }
        public var systemImage: String { self == .bar ? "chart.bar" : "chart.xyaxis.line" }
    }

    public enum DateInterval: String, Codable, CaseIterable, Sendable {
        case day = "tag"
        case week = "woche"
        case month = "monat"
        case year = "jahr"

        public var label: String {
            switch self {
            case .day: "Tag"
            case .week: "Woche"
            case .month: "Monat"
            case .year: "Jahr"
            }
        }
    }

    public enum ChartMeasure: String, Codable, CaseIterable, Sendable {
        case count = "anzahl"
        case sum = "summe"
        case average = "durchschnitt"

        public var label: String {
            switch self {
            case .count: "Anzahl"
            case .sum: "Summe"
            case .average: "Durchschnitt"
            }
        }
    }
}
