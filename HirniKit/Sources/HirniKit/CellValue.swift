import Foundation

/// Deutet die Rohwerte einer Datenbankzelle und schreibt sie zurück.
///
/// In der Datei stehen Werte bewusst einfach und ohne Ländereinstellung:
/// Zahl `42.5`, Datum `2026-10-24` oder `2026-10-24 14:30`, Zeitraum
/// `2026-10-24/2026-10-26`, Checkbox `ja`/`nein`, Mehrfachauswahl `A, B`.
public enum CellValue {
    // MARK: - Zahl

    /// Versteht auch `42,50`, `CHF 42.50`, `1'200` oder `12 %`.
    public static func number(_ raw: String) -> Double? {
        var cleaned = raw.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        cleaned = cleaned.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        // Ein Komma ohne Punkt ist ein Dezimalkomma, sonst ein Tausendertrenner.
        if cleaned.contains(",") {
            cleaned = cleaned.contains(".")
                ? cleaned.replacingOccurrences(of: ",", with: "")
                : cleaned.replacingOccurrences(of: ",", with: ".")
        }
        return Double(cleaned)
    }

    /// Rohwert für die Datei: Punkt als Dezimalzeichen, ohne unnötige Nullen.
    public static func raw(number: Double) -> String {
        if number == number.rounded(), abs(number) < 1e15 {
            return String(Int64(number))
        }
        var text = String(format: "%.10f", number)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    public static func display(number: Double, format: NumberFormat?) -> String {
        let locale = Locale(identifier: "de_CH")
        switch format ?? .plain {
        case .plain:
            return number.formatted(.number.locale(locale))
        case .chf:
            return number.formatted(.currency(code: "CHF").locale(locale))
        case .eur:
            return number.formatted(.currency(code: "EUR").locale(locale))
        case .usd:
            return number.formatted(.currency(code: "USD").locale(locale))
        case .percent:
            // 12 bedeutet 12 %, nicht 1200 %.
            return (number / 100).formatted(.percent.locale(locale))
        }
    }

    // MARK: - Datum

    public struct DateValue: Equatable, Sendable {
        public var start: Date
        public var end: Date?
        public var includesTime: Bool

        public init(start: Date, end: Date? = nil, includesTime: Bool = false) {
            self.start = start
            self.end = end
            self.includesTime = includesTime
        }
    }

    public static func date(_ raw: String) -> DateValue? {
        let parts = raw.split(separator: "/", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first, let start = parseDate(first) else { return nil }
        let end = parts.count > 1 ? parseDate(parts[1]) : nil
        return DateValue(start: start.date, end: end?.date, includesTime: start.hasTime || (end?.hasTime ?? false))
    }

    public static func raw(date value: DateValue) -> String {
        let format = value.includesTime ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        let start = formatter(format).string(from: value.start)
        guard let end = value.end else { return start }
        return start + "/" + formatter(format).string(from: end)
    }

    public static func display(date value: DateValue) -> String {
        func one(_ date: Date) -> String {
            value.includesTime
                ? date.formatted(.dateTime.locale(Locale(identifier: "de_CH")).day().month(.abbreviated).year().hour().minute())
                : date.formatted(.dateTime.locale(Locale(identifier: "de_CH")).day().month(.abbreviated).year())
        }
        guard let end = value.end else { return one(value.start) }
        return one(value.start) + " – " + one(end)
    }

    private static func parseDate(_ text: String) -> (date: Date, hasTime: Bool)? {
        if let date = formatter("yyyy-MM-dd HH:mm").date(from: text) { return (date, true) }
        if let date = formatter("yyyy-MM-dd'T'HH:mm").date(from: text) { return (date, true) }
        if let date = formatter("yyyy-MM-dd").date(from: text) { return (date, false) }
        if let date = formatter("dd.MM.yyyy").date(from: text) { return (date, false) } // so tippt man es in der Schweiz
        return nil
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    // MARK: - Checkbox

    public static func bool(_ raw: String) -> Bool {
        ["ja", "x", "true", "yes", "1", "[x]", "✓"].contains(raw.trimmingCharacters(in: .whitespaces).lowercased())
    }

    public static func raw(bool: Bool) -> String {
        bool ? "ja" : "nein"
    }

    // MARK: - Mehrfachauswahl

    public static func list(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public static func raw(list: [String]) -> String {
        list.joined(separator: ", ")
    }

    // MARK: - Anzeige allgemein

    /// Der Wert so, wie er in Tabelle und Liste erscheint. Passt ein Wert nicht
    /// zum Feldtyp, wird er unverändert gezeigt.
    public static func display(_ raw: String, for field: Field) -> String {
        switch field.type {
        case .number:
            return number(raw).map { display(number: $0, format: field.format) } ?? raw
        case .date:
            return date(raw).map(display(date:)) ?? raw
        case .checkbox:
            return bool(raw) ? "✓" : ""
        case .multiSelect:
            return list(raw).joined(separator: ", ")
        case .text, .select, .url:
            return raw
        }
    }

    /// `true`, wenn `raw` zum Feldtyp passt (leer passt immer). Für die
    /// Warnung beim Ändern eines Feldtyps.
    public static func fits(_ raw: String, _ field: Field) -> Bool {
        guard !raw.isEmpty else { return true }
        switch field.type {
        case .text: return true
        case .number: return number(raw) != nil
        case .date: return date(raw) != nil
        case .checkbox: return ["ja", "nein", "x", "true", "false", "yes", "no", "1", "0"].contains(raw.lowercased())
        case .select: return field.options?.contains(raw) ?? true
        case .multiSelect: return list(raw).allSatisfy { field.options?.contains($0) ?? true }
        case .url: return URL(string: raw)?.scheme != nil
        }
    }

    /// Wert nach dem Umbenennen von Optionen (`alt` → `neu`). Bei einer
    /// Mehrfachauswahl wird jede Option einzeln umbenannt.
    public static func renamingOptions(_ raw: String, _ renames: [String: String], type: FieldType) -> String {
        guard !renames.isEmpty, !raw.isEmpty else { return raw }
        switch type {
        case .select: return renames[raw] ?? raw
        case .multiSelect: return Self.raw(list: list(raw).map { renames[$0] ?? $0 })
        default: return raw
        }
    }

}
