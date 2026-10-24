import Foundation

/// Führt zwei Änderungen am selben Text zusammen, zeilenweise.
///
/// Typischer Fall: Du tippst in einer Notiz, und gleichzeitig ändert Claude
/// (oder das andere Gerät) dieselbe Datei. `base` ist der Stand, den der
/// Editor zuletzt geladen bzw. gespeichert hat, `mine` der Text im Editor,
/// `theirs` der neue Stand auf der Festplatte.
///
/// Betreffen die beiden Änderungen verschiedene Zeilen, werden beide
/// übernommen. Ändern beide dieselbe Stelle unterschiedlich, gibt es kein
/// Ergebnis (`nil`), und der Mensch muss entscheiden.
public enum ThreeWayMerge {
    /// Obergrenze für den Vergleich (Zeilen alt × Zeilen neu). Darüber wird
    /// nicht automatisch zusammengeführt.
    static let maxComparisons = 4_000_000

    public static func merge(base: String, mine: String, theirs: String) -> String? {
        if mine == theirs || base == theirs { return mine }
        if base == mine { return theirs }

        let baseLines = base.components(separatedBy: "\n")
        guard let mineHunks = hunks(from: baseLines, to: mine.components(separatedBy: "\n")),
              let theirHunks = hunks(from: baseLines, to: theirs.components(separatedBy: "\n"))
        else { return nil }

        // Gleiche Änderung auf beiden Seiten nur einmal übernehmen.
        let onlyTheirs = theirHunks.filter { !mineHunks.contains($0) }
        for a in mineHunks {
            for b in onlyTheirs where a.conflicts(with: b) {
                return nil
            }
        }

        let all = (mineHunks + onlyTheirs).sorted {
            // Bei gleichem Start zuerst reine Einfügungen.
            ($0.range.lowerBound, $0.range.isEmpty ? 0 : 1) < ($1.range.lowerBound, $1.range.isEmpty ? 0 : 1)
        }
        var result: [String] = []
        var position = 0
        for hunk in all {
            result += baseLines[position..<hunk.range.lowerBound]
            result += hunk.lines
            position = hunk.range.upperBound
        }
        result += baseLines[position...]
        return result.joined(separator: "\n")
    }

    /// Eine Änderung: Die Zeilen `range` des alten Texts werden durch `lines` ersetzt.
    struct Hunk: Equatable {
        let range: Range<Int>
        let lines: [String]

        func conflicts(with other: Hunk) -> Bool {
            if range.isEmpty && other.range.isEmpty {
                return range.lowerBound == other.range.lowerBound // zwei Einfügungen an derselben Stelle
            }
            if range.isEmpty { return other.range.lowerBound < range.lowerBound && range.lowerBound < other.range.upperBound }
            if other.range.isEmpty { return range.lowerBound < other.range.lowerBound && other.range.lowerBound < range.upperBound }
            return range.overlaps(other.range)
        }
    }

    /// Unterschiede zwischen zwei Zeilenlisten über die längste gemeinsame
    /// Teilfolge. `nil`, wenn die Texte für den Vergleich zu gross sind.
    static func hunks(from old: [String], to new: [String]) -> [Hunk]? {
        let n = old.count, m = new.count
        guard n * m <= maxComparisons else { return nil }

        // lcs[i][j] = Länge der gemeinsamen Teilfolge von old[i...] und new[j...]
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = old[i] == new[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        var hunks: [Hunk] = []
        var i = 0, j = 0
        var start: (old: Int, new: Int)?
        func close() {
            if let s = start {
                hunks.append(Hunk(range: s.old..<i, lines: Array(new[s.new..<j])))
                start = nil
            }
        }
        while i < n || j < m {
            if i < n, j < m, old[i] == new[j] {
                close()
                i += 1; j += 1
            } else {
                if start == nil { start = (i, j) }
                if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                    j += 1
                } else {
                    i += 1
                }
            }
        }
        close()
        return hunks
    }
}
