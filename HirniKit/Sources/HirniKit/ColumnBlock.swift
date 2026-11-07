import Foundation

/// Ein Bereich mit Spalten mitten in einer Notiz. In der Datei bleibt er
/// lesbarer Text, jede Spalte ist gewöhnliches Markdown:
///
/// ```
/// :::spalten
/// - Erste Spalte
/// :::spalte
/// | Zweite | Spalte |
/// |---|---|
/// :::
/// ```
public struct ColumnBlock: Equatable, Sendable {
    public static let openingLine = ":::spalten"
    public static let dividerLine = ":::spalte"
    public static let closingLine = ":::"

    public var columns: [String]
    /// Der ganze Block, von der ersten bis zur letzten Zeile (ohne Zeilenschaltung danach).
    public let range: NSRange
    /// Der Text jeder Spalte in der Notiz.
    public let columnRanges: [NSRange]

    public init(columns: [String], range: NSRange = NSRange(location: 0, length: 0), columnRanges: [NSRange] = []) {
        self.columns = columns
        self.range = range
        self.columnRanges = columnRanges
    }

    public static func empty(columns: Int = 2) -> ColumnBlock {
        ColumnBlock(columns: Array(repeating: "", count: columns))
    }

    public var markdown: String {
        ([Self.openingLine, columns.joined(separator: "\n\(Self.dividerLine)\n"), Self.closingLine])
            .joined(separator: "\n")
    }

    /// Ohne Spalten: der Text untereinander, durch Leerzeilen getrennt.
    public var dissolved: String {
        columns.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n\n")
    }

    /// Alle vollständigen Blöcke. Ein Block ohne Abschluss bleibt gewöhnlicher
    /// Text, Blöcke in Codeblöcken zählen nicht. Spalten lassen sich nicht schachteln.
    public static func blocks(in text: String) -> [ColumnBlock] {
        guard text.contains(openingLine) else { return [] }
        let ns = text as NSString
        var lines: [(text: String, range: NSRange)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines]) { line, range, _, _ in
            lines.append(((line ?? "").trimmingCharacters(in: .whitespaces), range))
        }

        var result: [ColumnBlock] = []
        var index = 0
        var inFence = false
        while index < lines.count {
            let line = lines[index].text
            if line.hasPrefix("```") { inFence.toggle() }
            guard !inFence, line == openingLine else { index += 1; continue }

            // Marken des Blocks suchen.
            var marks = [index]
            var cursor = index + 1
            var fence = false
            var closed = false
            while cursor < lines.count {
                let current = lines[cursor].text
                if current.hasPrefix("```") { fence.toggle() }
                if !fence {
                    if current == dividerLine { marks.append(cursor) }
                    if current == closingLine { marks.append(cursor); closed = true; break }
                }
                cursor += 1
            }
            guard closed else { index += 1; continue }

            var ranges: [NSRange] = []
            for (mark, next) in zip(marks, marks.dropFirst()) {
                if mark + 1 < next {
                    ranges.append(NSRange(lines[mark + 1].range.location..<NSMaxRange(lines[next - 1].range)))
                } else {
                    ranges.append(NSRange(location: lines[next].range.location, length: 0))
                }
            }
            result.append(ColumnBlock(
                columns: ranges.map { ns.substring(with: $0) },
                range: NSRange(lines[index].range.location..<NSMaxRange(lines[cursor].range)),
                columnRanges: ranges
            ))
            index = cursor + 1
        }
        return result
    }

    /// Die Spalte an dieser Stelle der Notiz, mit Position in der Spalte.
    public func column(at location: Int) -> (index: Int, offset: Int)? {
        for (index, range) in columnRanges.enumerated()
        where location >= range.location && location <= NSMaxRange(range) {
            return (index, location - range.location)
        }
        return nil
    }

    /// Lässt Elemente weg, die in einem Spalten-Block liegen: Dort zeigt sie
    /// der Editor der Spalte.
    static func outside<T>(_ items: [T], in text: String, range: (T) -> NSRange) -> [T] {
        let blocks = blocks(in: text)
        guard !blocks.isEmpty else { return items }
        return items.filter { item in
            !blocks.contains { NSIntersectionRange($0.range, range(item)).length > 0 }
        }
    }

    // MARK: - Bearbeiten

    public mutating func insertColumn(at index: Int) {
        columns.insert("", at: min(index, columns.count))
    }

    public mutating func moveColumn(from source: Int, to destination: Int) {
        guard columns.indices.contains(source), columns.indices.contains(destination) else { return }
        columns.insert(columns.remove(at: source), at: destination)
    }

    public mutating func removeColumn(at index: Int) {
        guard columns.count > 1, columns.indices.contains(index) else { return }
        columns.remove(at: index)
    }
}
