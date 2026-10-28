import Foundation

/// Eine Datenbank wie in Notion: Felder mit Typ und Zeilen mit Werten.
///
/// Gespeichert als **eine Markdown-Datei** `Name.hirnidb.md`:
///
/// ```
/// ---
/// hirni-datenbank: 1
/// felder:
///   - {"name": "Name", "typ": "text"}
///   - {"name": "Betrag", "typ": "zahl", "format": "chf"}
///   - {"name": "Kategorie", "typ": "auswahl", "optionen": ["Essen", "Reisen"]}
/// ---
/// | id | Name | Betrag | Kategorie |
/// |---|---|---|---|
/// | k3f9a2c1 | Pizza | 42.5 | Essen |
/// ```
///
/// Der Kopf ist gültiges YAML (jede Feldzeile ist ein JSON-Objekt), die
/// Tabelle gewöhnliches Markdown. So können Mensch, Claude und Obsidian die
/// Datei lesen. Werte werden als Text gespeichert und erst beim Anzeigen
/// gedeutet (siehe `CellValue`). Damit geht beim Lesen und Schreiben nichts
/// verloren, auch wenn ein Wert nicht zum Feldtyp passt.
public struct Database: Equatable, Sendable {
    public var fields: [Field]
    public var rows: [Row]
    /// Gespeicherte Ansichten (Filter, Sortierung …). Leer = nur die Standardansicht.
    public var views: [SavedView] = []
    /// Datumsfeld, dessen Einträge im Apple Kalender «Hirni» erscheinen
    /// (Kopfzeile `kalender: "Datum"`). `nil` = nicht im Kalender.
    public var calendarField: String?
    /// Zeilen im Kopf, die hirni nicht kennt (z. B. von Obsidian). Sie bleiben erhalten.
    public var otherHeaderLines: [String]
    /// Text vor bzw. nach der Tabelle. Bleibt erhalten.
    public var textBefore: String
    public var textAfter: String

    public init(fields: [Field], rows: [Row] = [], otherHeaderLines: [String] = [], textBefore: String = "", textAfter: String = "") {
        self.fields = fields
        self.rows = rows
        self.otherHeaderLines = otherHeaderLines
        self.textBefore = textBefore
        self.textAfter = textAfter
    }

    public func field(named name: String) -> Field? {
        fields.first { $0.name == name }
    }
}

public struct Field: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var type: FieldType
    /// Nur bei Zahlen.
    public var format: NumberFormat?
    /// Nur bei Auswahl und Mehrfachauswahl.
    public var options: [String]?
    /// Nur bei Datum: mit Uhrzeit.
    public var includesTime: Bool?

    public init(name: String, type: FieldType, format: NumberFormat? = nil, options: [String]? = nil, includesTime: Bool? = nil) {
        self.name = name
        self.type = type
        self.format = format
        self.options = options
        self.includesTime = includesTime
    }

    enum CodingKeys: String, CodingKey {
        case name
        case type = "typ"
        case format
        case options = "optionen"
        case includesTime = "zeit"
    }
}

/// Feldtypen. Der Rohwert steht so in der Datei.
public enum FieldType: String, Codable, CaseIterable, Sendable {
    case text
    case number = "zahl"
    case select = "auswahl"
    case multiSelect = "mehrfachauswahl"
    case date = "datum"
    case checkbox
    case url

    public var label: String {
        switch self {
        case .text: "Text"
        case .number: "Zahl"
        case .select: "Auswahl"
        case .multiSelect: "Mehrfachauswahl"
        case .date: "Datum"
        case .checkbox: "Checkbox"
        case .url: "URL"
        }
    }

    public var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .number: "number"
        case .select: "chevron.down.circle"
        case .multiSelect: "tag"
        case .date: "calendar"
        case .checkbox: "checkmark.square"
        case .url: "link"
        }
    }
}

public enum NumberFormat: String, Codable, CaseIterable, Sendable {
    case plain = "normal"
    case chf
    case eur
    case usd
    case percent = "prozent"

    public var label: String {
        switch self {
        case .plain: "Zahl"
        case .chf: "CHF"
        case .eur: "EUR"
        case .usd: "USD"
        case .percent: "Prozent"
        }
    }
}

public struct Row: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    /// Rohwerte nach Feldname. Fehlt ein Feld, ist der Wert leer.
    public var values: [String: String]

    public init(id: String = Row.newID(), values: [String: String] = [:]) {
        self.id = id
        self.values = values
    }

    public subscript(field: String) -> String {
        get { values[field] ?? "" }
        set { values[field] = newValue.isEmpty ? nil : newValue }
    }

    /// Kurze, zufällige Kennung aus Kleinbuchstaben und Ziffern.
    public static func newID() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<8).map { _ in characters.randomElement()! })
    }
}

// MARK: - Datei

public enum DatabaseFileError: LocalizedError, Equatable {
    case notADatabase
    case invalidField(line: String)

    public var errorDescription: String? {
        switch self {
        case .notADatabase:
            "Die Datei ist keine hirni-Datenbank (es fehlt «hirni-datenbank» im Kopf)."
        case .invalidField(let line):
            "Ein Feld im Kopf der Datei ist unlesbar: \(line)"
        }
    }
}

public enum DatabaseFile {
    public static let version = 1
    static let idColumn = "id"

    // MARK: Lesen

    public static func parse(_ text: String) throws -> Database {
        let (header, body) = Frontmatter.split(text)
        guard let header else { throw DatabaseFileError.notADatabase }

        var fields: [Field] = []
        var views: [SavedView] = []
        var calendarField: String?
        var otherLines: [String] = []
        var isDatabase = false
        enum Block { case none, fields, views }
        var block = Block.none
        for line in header.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("hirni-datenbank:") {
                isDatabase = true
                block = .none
            } else if trimmed == "felder:" {
                block = .fields
            } else if trimmed == "ansichten:" {
                block = .views
            } else if trimmed.hasPrefix("kalender:") {
                block = .none
                let value = trimmed.dropFirst("kalender:".count).trimmingCharacters(in: .whitespaces)
                calendarField = try? JSONDecoder().decode(String.self, from: Data(value.utf8))
            } else if block != .none, trimmed.hasPrefix("- ") {
                let data = Data(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces).utf8)
                switch block {
                case .fields:
                    guard let field = try? JSONDecoder().decode(Field.self, from: data) else {
                        throw DatabaseFileError.invalidField(line: trimmed)
                    }
                    fields.append(field)
                case .views:
                    // Eine kaputte Ansicht ist kein Grund, die Daten nicht zu zeigen.
                    if let view = try? JSONDecoder().decode(SavedView.self, from: data) { views.append(view) }
                case .none:
                    break
                }
            } else {
                block = .none
                otherLines.append(line)
            }
        }
        guard isDatabase else { throw DatabaseFileError.notADatabase }

        var database = Database(fields: fields, otherHeaderLines: otherLines)
        database.views = views
        database.calendarField = calendarField
        parseTable(body, into: &database)
        return database
    }

    private static func parseTable(_ body: String, into database: inout Database) {
        let lines = body.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { isTableLine($0) && cells(of: $0).first?.lowercased() == idColumn })
        else {
            database.textBefore = body.trimmingCharacters(in: .newlines)
            return
        }
        var end = start
        while end < lines.count, isTableLine(lines[end]) { end += 1 }

        // Leerzeilen rund um die Tabelle setzt `serialize` selbst.
        database.textBefore = lines[..<start].joined(separator: "\n").trimmingCharacters(in: .newlines)
        database.textAfter = lines[end...].joined(separator: "\n").trimmingCharacters(in: .newlines)

        let columns = cells(of: lines[start])
        // Spalten ohne Feld (z. B. von Claude ergänzt) werden zu Textfeldern.
        for name in columns.dropFirst() where !name.isEmpty && database.field(named: name) == nil {
            database.fields.append(Field(name: name, type: .text))
        }

        var seenIDs = Set<String>()
        for line in lines[(start + 1)..<end] {
            let values = cells(of: line)
            if values.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { continue } // Trennzeile |---|
            var id = values.first ?? ""
            if id.isEmpty || seenIDs.contains(id) { id = Row.newID() }
            seenIDs.insert(id)
            var row = Row(id: id)
            for (index, name) in columns.enumerated().dropFirst() where index < values.count {
                row[name] = values[index]
            }
            database.rows.append(row)
        }
    }

    private static func isTableLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("|")
    }

    /// Zellen einer Tabellenzeile, mit `\|` als maskiertem Strich und `<br>` als Zeilenumbruch.
    static func cells(of line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") && !trimmed.hasSuffix("\\|") { trimmed.removeLast() }

        var result: [String] = []
        var current = ""
        var escaped = false
        for character in trimmed {
            if escaped {
                // `\|` → `|`, `\\` → `\`, alles andere bleibt wie geschrieben.
                if character == "|" || character == "\\" {
                    current.append(character)
                } else {
                    current.append("\\")
                    current.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        result.append(current)
        return result.map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "<br>", with: "\n")
        }
    }

    // MARK: Schreiben

    public static func serialize(_ database: Database) -> String {
        var header = ["hirni-datenbank: \(version)", "felder:"]
        let encoder = JSONEncoder()
        // Feste Schlüsselreihenfolge: Sonst ändert sich die Datei bei jedem Speichern.
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        for field in database.fields {
            let json = (try? encoder.encode(field)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            header.append("  - \(json)")
        }
        if !database.views.isEmpty {
            header.append("ansichten:")
            for view in database.views {
                let json = (try? encoder.encode(view)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                header.append("  - \(json)")
            }
        }
        if let field = database.calendarField,
           let json = (try? encoder.encode(field)).flatMap({ String(data: $0, encoding: .utf8) }) {
            header.append("kalender: \(json)")
        }
        header += database.otherHeaderLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let columns = [idColumn] + database.fields.map(\.name)
        var table = [line(columns), "|" + String(repeating: "---|", count: columns.count)]
        for row in database.rows {
            table.append(line([row.id] + database.fields.map { row[$0.name] }))
        }

        var parts: [String] = []
        if !database.textBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(database.textBefore.trimmingCharacters(in: .newlines))
            parts.append("")
        }
        parts += table
        if !database.textAfter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("")
            parts.append(database.textAfter.trimmingCharacters(in: .newlines))
        }
        return Frontmatter.join(header: header.joined(separator: "\n"), body: parts.joined(separator: "\n") + "\n")
    }

    private static func line(_ cells: [String]) -> String {
        "| " + cells.map(escape).joined(separator: " | ") + " |"
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}

extension Database {
    /// Verschiebt ein Feld vor `target` (bzw. ans Ende bei `nil`). Die Werte
    /// bleiben, wo sie sind: Zeilen speichern ihre Werte nach Feldname.
    public mutating func moveField(_ name: String, before target: String?) {
        guard name != target, let from = fields.firstIndex(where: { $0.name == name }) else { return }
        let field = fields.remove(at: from)
        let to = target.flatMap { target in fields.firstIndex { $0.name == target } } ?? fields.endIndex
        fields.insert(field, at: to)
    }
}
