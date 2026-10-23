import Foundation
import SQLite3

/// Ein Treffer der Volltextsuche.
public struct SearchHit: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let title: String
    /// Ordner relativ zum hirni-Ordner, z. B. `Privat/Ferien` (leer = oberste Ebene).
    public let folder: String
    /// Textausschnitt um den Treffer. Gefundene Wörter stehen zwischen
    /// `SearchHit.highlightStart` und `SearchHit.highlightEnd`.
    public let snippet: String

    public static let highlightStart: Character = "\u{1}"
    public static let highlightEnd: Character = "\u{2}"
}

/// Lokaler Such-Index pro Gerät (SQLite mit FTS5), gespeichert im
/// Cache-Ordner. Er wird nicht synchronisiert und lässt sich jederzeit aus
/// den Dateien neu aufbauen. Gelöscht vom System? Dann entsteht er beim
/// nächsten Start einfach neu.
public actor SearchIndex {
    private let db: OpaquePointer

    public init(fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(fileURL.path(percentEncoded: false), &handle,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle
        else { throw SearchIndexError.cannotOpen }
        db = handle
        try Self.exec(db, """
            CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, modified REAL NOT NULL);
            CREATE VIRTUAL TABLE IF NOT EXISTS texts USING fts5(
                path UNINDEXED, title, body, tokenize = 'unicode61 remove_diacritics 2'
            );
            CREATE TABLE IF NOT EXISTS tags (path TEXT NOT NULL, tag TEXT NOT NULL, lowered TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS tags_lowered ON tags (lowered);
            CREATE INDEX IF NOT EXISTS tags_path ON tags (path);
            """)
    }

    isolated deinit {
        sqlite3_close(db)
    }

    // MARK: - Aktualisieren

    /// Gleicht den Index mit den Dateien ab. Gelesen werden nur Notizen, die
    /// neu sind oder sich geändert haben. Liefert die Zahl der neu gelesenen.
    @discardableResult
    public func update(from vault: Vault) throws -> Int {
        var known: [String: Double] = [:]
        try query("SELECT path, modified FROM files") { row in
            known[row.text(0)] = row.double(1)
        }

        var seen = Set<String>()
        var changed = 0
        try Self.exec(db, "BEGIN")
        do {
            for url in vault.allNoteURLs() {
                guard let path = vault.relativePath(of: url) else { continue }
                seen.insert(path)
                let modified = vault.modificationDate(of: url)?.timeIntervalSinceReferenceDate ?? 0
                if let old = known[path], abs(old - modified) < 0.001 { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                try store(path: path, title: Vault.title(of: url), text: text, modified: modified)
                changed += 1
            }
            for path in known.keys where !seen.contains(path) {
                try remove(path: path)
                changed += 1
            }
            try Self.exec(db, "COMMIT")
        } catch {
            try? Self.exec(db, "ROLLBACK")
            throw error
        }
        return changed
    }

    private func store(path: String, title: String, text: String, modified: Double) throws {
        try remove(path: path)
        let body = Frontmatter.split(text).body
        try run("INSERT INTO texts (path, title, body) VALUES (?, ?, ?)", path, title, body)
        try run("INSERT INTO files (path, modified) VALUES (?, ?)", path, modified)
        for tag in MarkdownSyntax.tags(in: body) {
            try run("INSERT INTO tags (path, tag, lowered) VALUES (?, ?, ?)", path, tag, tag.lowercased())
        }
    }

    private func remove(path: String) throws {
        try run("DELETE FROM texts WHERE path = ?", path)
        try run("DELETE FROM files WHERE path = ?", path)
        try run("DELETE FROM tags WHERE path = ?", path)
    }

    // MARK: - Abfragen

    /// Volltextsuche über Titel und Text. Jedes Wort muss vorkommen (auch als
    /// Wortanfang: «ferie» findet «Ferien»). Gross/klein und Akzente spielen
    /// keine Rolle. `folder` schränkt auf einen Ordner samt Unterordnern ein.
    public func search(_ text: String, in folder: String? = nil, vault: Vault, limit: Int = 100) throws -> [SearchHit] {
        guard let match = Self.matchExpression(for: text) else { return [] }
        var sql = """
            SELECT path, title, snippet(texts, 2, char(1), char(2), '…', 12)
            FROM texts WHERE texts MATCH ?
            """
        var arguments: [any SQLiteValue] = [match]
        if let folder, !folder.isEmpty {
            sql += " AND (path LIKE ? ESCAPE '\\')"
            arguments.append(Self.likePrefix(folder))
        }
        sql += " ORDER BY bm25(texts, 0, 10, 1) LIMIT \(limit)"

        var hits: [SearchHit] = []
        try query(sql, arguments) { row in
            let path = row.text(0)
            hits.append(SearchHit(
                url: vault.root.appending(path: path),
                title: row.text(1),
                folder: (path as NSString).deletingLastPathComponent,
                snippet: row.text(2)
            ))
        }
        return hits
    }

    /// Alle Notizen mit einem Tag (Gross/klein egal). Mit `includeChildren`
    /// zählt `#ferien/2026` auch für `ferien`.
    public func notes(withTag tag: String, includeChildren: Bool = true, vault: Vault) throws -> [URL] {
        let lowered = tag.lowercased()
        var paths: [String] = []
        try query(
            "SELECT DISTINCT path FROM tags WHERE lowered = ? OR (? AND lowered LIKE ? ESCAPE '\\') ORDER BY path",
            [lowered, includeChildren ? 1 : 0, Self.likePrefix(lowered)]
        ) { row in
            paths.append(row.text(0))
        }
        return paths.map { vault.root.appending(path: $0) }
    }

    /// Alle Tags mit der Anzahl Notizen, die häufigsten zuerst.
    public func tags() throws -> [(name: String, count: Int)] {
        var result: [(String, Int)] = []
        try query("""
            SELECT MIN(tag), COUNT(DISTINCT path) AS n FROM tags
            GROUP BY lowered ORDER BY n DESC, lowered
            """) { row in
            result.append((row.text(0), row.int(1)))
        }
        return result
    }

    // MARK: - Suchausdruck

    /// Macht aus der Eingabe einen sicheren FTS5-Ausdruck: jedes Wort in
    /// Anführungszeichen und mit `*` (Wortanfang), verbunden mit UND.
    static func matchExpression(for input: String) -> String? {
        let words = input
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    /// `Privat/Ferien` → `Privat/Ferien/%` mit maskierten `%` und `_`.
    static func likePrefix(_ folder: String) -> String {
        let escaped = folder
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return escaped + "/%"
    }

    // MARK: - SQLite

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SearchIndexError.sql(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func run(_ sql: String, _ arguments: any SQLiteValue...) throws {
        try query(sql, arguments) { _ in }
    }

    private func query(_ sql: String, _ arguments: [any SQLiteValue] = [], row handle: (Row) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SearchIndexError.sql(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in arguments.enumerated() {
            value.bind(to: statement, at: Int32(index + 1))
        }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: handle(Row(statement: statement))
            case SQLITE_DONE: return
            default: throw SearchIndexError.sql(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private struct Row {
        let statement: OpaquePointer
        func text(_ column: Int32) -> String {
            sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        }
        func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
        func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
    }
}

public enum SearchIndexError: Error {
    case cannotOpen
    case sql(String)
}

/// Werte, die an eine SQL-Abfrage übergeben werden können.
protocol SQLiteValue: Sendable {
    func bind(to statement: OpaquePointer, at index: Int32)
}

/// SQLite soll den Text sofort kopieren (die Swift-Zeichenkette lebt nur kurz).
private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension String: SQLiteValue {
    func bind(to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, self, -1, transient)
    }
}

extension Double: SQLiteValue {
    func bind(to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_double(statement, index, self)
    }
}

extension Int: SQLiteValue {
    func bind(to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_int64(statement, index, Int64(self))
    }
}
