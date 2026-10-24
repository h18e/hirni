import Foundation

/// Der hirni-Ordner mit allen Datei-Operationen.
///
/// Alle Methoden arbeiten synchron und direkt auf dem Dateisystem. Die App ruft
/// sie deshalb ausserhalb des Hauptthreads auf.
public struct Vault: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var inboxURL: URL {
        root.appending(path: VaultLayout.inboxFolderName, directoryHint: .isDirectory)
    }

    public var trashURL: URL {
        root.appending(path: VaultLayout.trashFolderName, directoryHint: .isDirectory)
    }

    private var fileManager: FileManager { .default }

    // MARK: - Lesen der Struktur

    /// Alle eigenen Ordner als Baum, alphabetisch. Inbox und Systemordner fehlen,
    /// die zeigt die Seitenleiste separat.
    public func folderTree() throws -> [FolderNode] {
        try subfolders(of: root).filter { $0.name != VaultLayout.inboxFolderName }
    }

    private func subfolders(of folder: URL) throws -> [FolderNode] {
        try entries(in: folder)
            .filter { $0.isDirectory && !VaultLayout.isSystemFolder(named: $0.name) }
            .map { FolderNode(url: $0.url, name: $0.name, children: try subfolders(of: $0.url)) }
    }

    /// Die Notizen direkt in `folder` (nicht in Unterordnern): angepinnte
    /// zuerst, sonst neueste zuerst.
    public func notes(in folder: URL) throws -> [NoteSummary] {
        try entries(in: folder)
            .filter { !$0.isDirectory && (Self.isNote(name: $0.name) || Self.isDatabase($0.url)) }
            .map { entry in
                let head = entry.isDownloaded ? beginning(of: entry.url) : ""
                let preview = Self.isDatabase(entry.url)
                    ? (entry.isDownloaded ? Self.databasePreview((try? String(contentsOf: entry.url, encoding: .utf8)) ?? "") : "Datenbank")
                    : NotePreview.make(from: head)
                return NoteSummary(
                    url: entry.url,
                    title: Self.title(of: entry.url),
                    modified: entry.modified,
                    preview: preview,
                    isDownloaded: entry.isDownloaded,
                    isPinned: Frontmatter.value(Frontmatter.pinnedKey, in: head) == "true"
                )
            }
            .sorted { a, b in
                a.isPinned != b.isPinned ? a.isPinned : a.modified > b.modified
            }
    }

    /// Listeneinträge für einzelne Notizen aus verschiedenen Ordnern
    /// (Tag-Ansicht), neueste zuerst.
    public func summaries(for urls: [URL]) -> [NoteSummary] {
        urls.compactMap { url -> NoteSummary? in
            guard let modified = modificationDate(of: url) else { return nil }
            let head = beginning(of: url)
            return NoteSummary(
                url: url,
                title: Self.title(of: url),
                modified: modified,
                preview: NotePreview.make(from: head),
                isDownloaded: true,
                isPinned: Frontmatter.value(Frontmatter.pinnedKey, in: head) == "true"
            )
        }
        .sorted { $0.modified > $1.modified }
    }

    static func isNote(name: String) -> Bool {
        name.lowercased().hasSuffix(".\(VaultLayout.noteExtension)")
            && !name.lowercased().hasSuffix(VaultLayout.databaseSuffix)
    }

    /// Titel = Dateiname ohne `.md` bzw. `.hirnidb.md`.
    public static func title(of noteURL: URL) -> String {
        let name = noteURL.deletingPathExtension().lastPathComponent
        return isDatabase(noteURL) ? String(name.dropLast(".hirnidb".count)) : name
    }

    /// Liest nur den Anfang der Datei – für Vorschau und YAML-Kopf reicht das.
    private func beginning(of url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 2048)) ?? Data()
        // Ein abgeschnittenes Mehrbyte-Zeichen am Ende darf nicht stören.
        return String(decoding: data, as: UTF8.self)
    }

    struct Entry {
        let url: URL
        let name: String
        let isDirectory: Bool
        let isDownloaded: Bool
        let modified: Date
    }

    /// Inhalt eines Ordners. iCloud-Platzhalter (`.Notiz.md.icloud`) erscheinen
    /// unter ihrem echten Namen, andere versteckte Dateien fehlen.
    func entries(in folder: URL) throws -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        let urls = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
        var result: [Entry] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let modified = values?.contentModificationDate ?? .distantPast
            let name = url.lastPathComponent
            if let realName = ICloudPlaceholder.realName(forPlaceholder: name) {
                result.append(Entry(
                    url: folder.appending(path: realName), name: realName,
                    isDirectory: false, isDownloaded: false, modified: modified
                ))
            } else if !name.hasPrefix(".") {
                result.append(Entry(
                    url: url, name: name,
                    isDirectory: values?.isDirectory ?? false, isDownloaded: true, modified: modified
                ))
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Notizen

    public func readNote(at url: URL) throws -> String {
        try Coordinated.read(url) { try String(contentsOf: $0, encoding: .utf8) }
    }

    /// Schreibt den Text und liefert das neue Änderungsdatum der Datei zurück.
    @discardableResult
    public func writeNote(_ text: String, to url: URL) throws -> Date {
        try Coordinated.write(url) { url in
            try Data(text.utf8).write(to: url, options: .atomic)
            return try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .now
        }
    }

    /// Frisch vom Dateisystem gelesen (eine `URL` merkt sich Werte sonst).
    public func modificationDate(of url: URL) -> Date? {
        try? URL(filePath: url.path(percentEncoded: false))
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    public func createNote(in folder: URL, title: String = "Neue Notiz", text: String = "") throws -> URL {
        let url = FileNaming.uniqueURL(
            in: folder, baseName: FileNaming.sanitized(title), pathExtension: VaultLayout.noteExtension
        )
        try Coordinated.write(url, options: .forReplacing) { url in
            try Data(text.utf8).write(to: url, options: .withoutOverwriting)
        }
        return url
    }

    /// Benennt die Notiz um und liefert die neue Adresse. Ist der Titel schon
    /// vergeben, wird eine Nummer angehängt («Einkauf 2»).
    public func renameNote(at url: URL, to title: String) throws -> URL {
        let target = FileNaming.uniqueURL(
            in: url.deletingLastPathComponent(),
            baseName: FileNaming.sanitized(title),
            pathExtension: FileNaming.split(url.lastPathComponent).pathExtension,
            excluding: url
        )
        try moveIfNeeded(from: url, to: target)
        return target
    }

    // MARK: - Ordner

    public func createFolder(in parent: URL, name: String) throws -> URL {
        let url = FileNaming.uniqueURL(in: parent, baseName: folderName(name), pathExtension: nil)
        try Coordinated.write(url, options: .forReplacing) { url in
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        }
        return url
    }

    public func renameFolder(at url: URL, to name: String) throws -> URL {
        let target = FileNaming.uniqueURL(
            in: url.deletingLastPathComponent(), baseName: folderName(name), pathExtension: nil, excluding: url
        )
        try moveIfNeeded(from: url, to: target)
        return target
    }

    /// Eigene Ordner dürfen nicht mit `_` beginnen, sonst würden sie als
    /// Systemordner ausgeblendet.
    private func folderName(_ name: String) -> String {
        var sanitized = FileNaming.sanitized(name)
        while sanitized.hasPrefix("_") { sanitized.removeFirst() }
        return sanitized.isEmpty ? "Neuer Ordner" : sanitized
    }

    // MARK: - Hilfen

    func moveIfNeeded(from source: URL, to target: URL) throws {
        guard source.standardizedFileURL != target.standardizedFileURL else { return }
        // Nur Gross-/Kleinschreibung geändert («einkauf» → «Einkauf»): Das
        // Dateisystem unterscheidet das nicht, darum über einen Zwischennamen.
        if source.lastPathComponent.lowercased() == target.lastPathComponent.lowercased() {
            let temp = source.deletingLastPathComponent().appending(path: ".hirni-umbenennen-\(UUID().uuidString)")
            try Coordinated.move(from: source, to: temp)
            try Coordinated.move(from: temp, to: target)
        } else {
            try Coordinated.move(from: source, to: target)
        }
    }

    /// `true`, wenn `url` im hirni-Ordner liegt.
    public func contains(_ url: URL) -> Bool {
        relativePath(of: url) != nil
    }

    /// Pfad von `url` relativ zum hirni-Ordner, z. B. `Privat/Ferien/Packliste.md`.
    public func relativePath(of url: URL) -> String? {
        let rootParts = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let parts = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard parts.count > rootParts.count, Array(parts.prefix(rootParts.count)) == rootParts else {
            return nil
        }
        return parts.dropFirst(rootParts.count).joined(separator: "/")
    }
}
