import Foundation

/// Zeilen-Seiten: zu einer Zeile einer Datenbank eine eigene Notiz.
///
/// ```
/// Privat/
/// ├── Ausgaben.hirnidb.md
/// └── Ausgaben/
///     └── Restaurant Bern.md   ← Kopf: hirni-zeile: k3f9a2c1
/// ```
///
/// Die Zuordnung läuft über die `id` im Kopf, nicht über den Dateinamen. Die
/// Seite darf also umbenannt werden, und eine geänderte Zeile behält ihre Seite.
extension Vault {
    public static let rowKey = "hirni-zeile"

    /// Der Ordner mit den Zeilen-Seiten, neben der Datenbank und gleich benannt.
    public static func rowPagesFolder(for database: URL) -> URL {
        database.deletingLastPathComponent()
            .appending(path: title(of: database), directoryHint: .isDirectory)
    }

    /// Alle Zeilen-Seiten der Datenbank: `id` → Seite. Gibt es zu einer `id`
    /// mehrere, gilt die alphabetisch erste. Noch nicht geladene
    /// iCloud-Dateien fehlen, weil ihr Kopf unbekannt ist.
    public func rowPages(for database: URL) -> [String: URL] {
        let folder = Self.rowPagesFolder(for: database)
        guard let entries = try? entries(in: folder) else { return [:] }
        var pages: [String: URL] = [:]
        for entry in entries where !entry.isDirectory && entry.isDownloaded && Self.isNote(name: entry.name) {
            guard let id = Frontmatter.value(Self.rowKey, in: beginning(of: entry.url)), !id.isEmpty,
                  pages[id] == nil
            else { continue }
            pages[id] = entry.url
        }
        return pages
    }

    /// Liefert die Seite der Zeile oder legt sie an. Der Dateiname kommt vom
    /// Titel der Zeile (erstes Feld), sonst «Eintrag». Mit `template` wird
    /// der Text aus der Vorlage übernommen, `values` füllt `{{Feldname}}` aus.
    public func rowPage(
        for database: URL, rowID: String, title: String,
        template: URL? = nil, values: [String: String] = [:], now: Date = .now
    ) throws -> URL {
        if let existing = rowPages(for: database)[rowID] { return existing }
        let folder = Self.rowPagesFolder(for: database)
        try Coordinated.write(folder, options: .forReplacing) { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Eintrag" : trimmed
        let body = try template.map {
            TemplateFiller.noteText(fromTemplate: try readNote(at: $0), title: name, date: now, values: values)
        } ?? ""
        let text = Frontmatter.setting(Self.rowKey, to: rowID, in: body)
        return try createNote(in: folder, title: name, text: text)
    }

    /// Nach Umbenennen oder Verschieben einer Datenbank zieht ihr Seiten-Ordner
    /// mit. Ist der neue Name schon belegt, bleibt er, wo er ist.
    func moveRowPages(from oldDatabase: URL, to newDatabase: URL) throws {
        let source = Self.rowPagesFolder(for: oldDatabase)
        let target = Self.rowPagesFolder(for: newDatabase)
        var isFolder: ObjCBool = false
        guard source.standardizedFileURL != target.standardizedFileURL,
              FileManager.default.fileExists(atPath: source.path(percentEncoded: false), isDirectory: &isFolder),
              isFolder.boolValue,
              !FileManager.default.fileExists(atPath: target.path(percentEncoded: false))
        else { return }
        try moveIfNeeded(from: source, to: target)
    }
}
