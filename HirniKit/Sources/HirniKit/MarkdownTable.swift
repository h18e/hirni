import Foundation

/// Eine gewöhnliche Markdown-Tabelle in einer Notiz:
///
/// ```
/// | Was | Wann |
/// |---|---|
/// | Zoo | Samstag |
/// ```
///
/// Die erste Zeile ist der Kopf. Ein `|` in einer Zelle steht als `\|`,
/// ein Zeilenumbruch als `<br>` in der Datei (wie bei Datenbanken).
public struct MarkdownTable: Equatable, Sendable {
    /// Alle Zeilen, die erste ist der Kopf. Jede Zeile hat gleich viele Zellen.
    public var rows: [[String]]
    /// Bereich im Text, ohne die letzte Zeilenschaltung.
    public var range: NSRange

    public init(rows: [[String]], range: NSRange = NSRange(location: 0, length: 0)) {
        self.rows = Self.padded(rows)
        self.range = range
    }

    public var columnCount: Int { rows.first?.count ?? 0 }

    /// Alle Tabellen im Text. Eine Tabelle braucht Kopf und Trennzeile
    /// (`|---|`). Tabellen in Codeblöcken zählen nicht.
    public static func tables(in text: String) -> [MarkdownTable] {
        let ns = text as NSString
        var lines: [(text: String, range: NSRange)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines]) { line, range, _, _ in
            lines.append((line ?? "", range))
        }
        var result: [MarkdownTable] = []
        var index = 0
        var inFence = false
        while index < lines.count {
            let line = lines[index].text.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inFence.toggle(); index += 1; continue }
            guard !inFence, isRow(line), index + 1 < lines.count,
                  isSeparator(lines[index + 1].text.trimmingCharacters(in: .whitespaces))
            else { index += 1; continue }
            var rows = [cells(of: line)]
            var end = index + 1
            while end + 1 < lines.count, isRow(lines[end + 1].text.trimmingCharacters(in: .whitespaces)) {
                end += 1
                rows.append(cells(of: lines[end].text.trimmingCharacters(in: .whitespaces)))
            }
            let range = NSRange(lines[index].range.location..<NSMaxRange(lines[end].range))
            result.append(MarkdownTable(rows: rows, range: range))
            index = end + 1
        }
        return result
    }

    /// Der Text der Tabelle, Spalten mit `|`, ohne abschliessende Zeilenschaltung.
    public var markdown: String {
        let rows = Self.padded(rows)
        guard let header = rows.first else { return "" }
        func line(_ cells: [String]) -> String {
            "| " + cells.map(Self.escape).joined(separator: " | ") + " |"
        }
        var lines = [line(header), "|" + String(repeating: "---|", count: header.count)]
        lines += rows.dropFirst().map(line)
        return lines.joined(separator: "\n")
    }

    /// Eine neue, leere Tabelle zum Einfügen.
    public static func empty(columns: Int = 3, rows: Int = 2) -> MarkdownTable {
        let header = (1...columns).map { "Spalte \($0)" }
        return MarkdownTable(rows: [header] + Array(repeating: Array(repeating: "", count: columns), count: rows))
    }

    // MARK: - Ändern

    public mutating func insertRow(at index: Int) {
        rows.insert(Array(repeating: "", count: columnCount), at: max(1, min(index, rows.count)))
    }

    public mutating func removeRow(at index: Int) {
        guard rows.count > 2, rows.indices.contains(index), index > 0 else { return }
        rows.remove(at: index)
    }

    public mutating func insertColumn(at index: Int) {
        let index = max(0, min(index, columnCount))
        for row in rows.indices { rows[row].insert(row == 0 ? "Spalte \(columnCount + 1)" : "", at: index) }
    }

    public mutating func removeColumn(at index: Int) {
        guard columnCount > 1, (0..<columnCount).contains(index) else { return }
        for row in rows.indices { rows[row].remove(at: index) }
    }

    public mutating func moveColumn(from source: Int, to target: Int) {
        guard (0..<columnCount).contains(source), (0..<columnCount).contains(target), source != target else { return }
        for row in rows.indices { rows[row].insert(rows[row].remove(at: source), at: target) }
    }

    public mutating func moveRow(from source: Int, to target: Int) {
        guard source > 0, target > 0, rows.indices.contains(source), rows.indices.contains(target), source != target else { return }
        rows.insert(rows.remove(at: source), at: target)
    }

    /// Ziehen am Rand: auf `count` Spalten bzw. Zeilen bringen. Entfernt
    /// werden nur leere Spalten/Zeilen am Ende (ein leerer Kopf «Spalte N» zählt als leer).
    public mutating func resize(columns: Int? = nil, bodyRows: Int? = nil) {
        if let columns {
            while columnCount < columns { insertColumn(at: columnCount) }
            while columnCount > max(1, columns), isEmptyColumn(columnCount - 1) { removeColumn(at: columnCount - 1) }
        }
        if let bodyRows {
            while rows.count - 1 < bodyRows { insertRow(at: rows.count) }
            while rows.count - 1 > max(1, bodyRows), rows.last?.allSatisfy({ $0.isEmpty }) == true { rows.removeLast() }
        }
    }

    public func isEmptyColumn(_ index: Int) -> Bool {
        rows.indices.allSatisfy { row in
            let value = rows[row][index]
            return value.isEmpty || (row == 0 && value.hasPrefix("Spalte "))
        }
    }

    // MARK: - Hilfen

    static func isRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.count >= 2
    }

    static func isSeparator(_ line: String) -> Bool {
        guard isRow(line) else { return false }
        let cells = cells(of: line)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= 1 && trimmed.allSatisfy { "-:".contains($0) } && trimmed.contains("-")
        }
    }

    /// Zellen einer Zeile, `\|` bleibt im Wert, `<br>` wird zum Zeilenumbruch.
    static func cells(of line: String) -> [String] {
        var body = Substring(line)
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|") && !body.hasSuffix("\\|") { body = body.dropLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for char in body {
            if escaped {
                // Nur `\|` ist eine Maskierung, andere `\` bleiben stehen.
                if char != "|" { current.append("\\") }
                current.append(char)
                escaped = false
                continue
            }
            if char == "\\" { escaped = true; continue }
            if char == "|" { cells.append(current); current = ""; continue }
            current.append(char)
        }
        if escaped { current.append("\\") }
        cells.append(current)
        return cells.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "<br>", with: "\n") }
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>")
    }

    static func padded(_ rows: [[String]]) -> [[String]] {
        let width = max(1, rows.map(\.count).max() ?? 1)
        return rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }
}
