import Foundation

extension Vault {
    public static func isDatabase(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased().hasSuffix(VaultLayout.databaseSuffix)
    }

    /// Legt eine leere Datenbank mit einem Textfeld «Name» an.
    public func createDatabase(in folder: URL, title: String = "Neue Datenbank") throws -> URL {
        let url = FileNaming.uniqueURL(
            in: folder,
            baseName: FileNaming.sanitized(title),
            pathExtension: String(VaultLayout.databaseSuffix.dropFirst())
        )
        let database = Database(fields: [Field(name: "Name", type: .text)])
        try Coordinated.write(url, options: .forReplacing) { url in
            try Data(DatabaseFile.serialize(database).utf8).write(to: url, options: .withoutOverwriting)
        }
        return url
    }

    public func readDatabase(at url: URL) throws -> Database {
        try DatabaseFile.parse(readNote(at: url))
    }

    @discardableResult
    public func writeDatabase(_ database: Database, to url: URL) throws -> Date {
        try writeNote(DatabaseFile.serialize(database), to: url)
    }

    /// Kurzbeschreibung für die Liste: «Datenbank · 12 Einträge».
    static func databasePreview(_ text: String) -> String {
        guard let database = try? DatabaseFile.parse(text) else { return "Datenbank (unlesbar)" }
        let count = database.rows.count
        return "Datenbank · \(count) \(count == 1 ? "Eintrag" : "Einträge")"
    }
}

/// Führt gleichzeitige Änderungen an einer Datenbank zusammen, Zelle für Zelle.
///
/// `base` ist der zuletzt geladene/gespeicherte Stand, `mine` der Stand in der
/// App, `theirs` der neue Stand der Datei. Hat nur eine Seite eine Zelle
/// geändert, gilt diese Änderung. Haben beide dieselbe Zelle verschieden
/// geändert, gewinnt `mine`. Die Zahl solcher Zellen wird gemeldet.
public enum DatabaseMerge {
    public struct Result: Equatable, Sendable {
        public let database: Database
        /// Zellen, die auf beiden Seiten verschieden geändert wurden.
        public let conflicts: Int
    }

    public static func merge(base: Database, mine: Database, theirs: Database) -> Result {
        var conflicts = 0

        // Felder: wer sie geändert hat, gewinnt. Beide geändert → meine.
        var merged = mine
        if mine.fields == base.fields { merged.fields = theirs.fields }
        if mine.otherHeaderLines == base.otherHeaderLines { merged.otherHeaderLines = theirs.otherHeaderLines }
        if mine.textBefore == base.textBefore { merged.textBefore = theirs.textBefore }
        if mine.textAfter == base.textAfter { merged.textAfter = theirs.textAfter }

        let baseRows = Dictionary(base.rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let mineRows = Dictionary(mine.rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let theirRows = Dictionary(theirs.rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var rows: [Row] = []
        // Reihenfolge: meine Zeilen, dabei neue Zeilen der anderen Seite an ihrer Stelle einfügen.
        var order = mine.rows.map(\.id)
        for (index, row) in theirs.rows.enumerated() where mineRows[row.id] == nil && baseRows[row.id] == nil {
            let previous = index > 0 ? theirs.rows[index - 1].id : nil
            let position = previous.flatMap { order.firstIndex(of: $0).map { $0 + 1 } } ?? order.count
            order.insert(row.id, at: min(position, order.count))
        }

        for id in order {
            let b = baseRows[id], m = mineRows[id], t = theirRows[id]
            switch (b, m, t) {
            case (nil, let m?, _):            // von mir neu
                rows.append(m)
            case (nil, nil, let t?):          // von der anderen Seite neu
                rows.append(t)
            case (let b?, let m?, let t?):    // beide haben die Zeile
                var row = m
                for key in Set(b.values.keys).union(m.values.keys).union(t.values.keys) {
                    let bv = b[key], mv = m[key], tv = t[key]
                    if mv == bv { row[key] = tv }
                    else if tv != bv && tv != mv { conflicts += 1 }
                }
                rows.append(row)
            case (let b?, let m?, nil):       // anderswo gelöscht
                if m != b {
                    conflicts += 1            // hier geändert: behalten
                    rows.append(m)
                }
            case (_?, nil, _):                // hier gelöscht
                break
            default:
                break
            }
        }
        merged.rows = rows
        return Result(database: merged, conflicts: conflicts)
    }
}
