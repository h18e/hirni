import Foundation

/// «Zuletzt gelöscht»: Gelöschtes wird nicht entfernt, sondern verschoben.
///
/// Jedes gelöschte Element bekommt eine eigene Hülle, damit gleichnamige
/// Notizen aus verschiedenen Ordnern sich nicht in die Quere kommen:
///
/// ```
/// _Zuletzt gelöscht/
/// └── 20261023-201512-1A2B3C4D/
///     ├── .hirni-geloescht.json   ← ursprünglicher Pfad + Löschdatum
///     └── Einkauf.md
/// ```
extension Vault {
    static let trashInfoFileName = ".hirni-geloescht.json"
    public static let trashRetentionDays = 30

    struct TrashInfo: Codable {
        var originalPath: String
        var deletedAt: Date
    }

    public func moveToTrash(_ url: URL, now: Date = .now) throws {
        let originalPath = relativePath(of: url) ?? url.lastPathComponent

        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: now)
        let stamp = String(
            format: "%04d%02d%02d-%02d%02d%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
        let container = trashURL.appending(
            path: "\(stamp)-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

        let info = TrashInfo(originalPath: originalPath, deletedAt: now)
        try Self.jsonEncoder.encode(info).write(to: container.appending(path: Self.trashInfoFileName))

        try Coordinated.move(from: url, to: container.appending(path: url.lastPathComponent))
    }

    public func trashEntries() throws -> [TrashEntry] {
        guard FileManager.default.fileExists(atPath: trashURL.path(percentEncoded: false)) else { return [] }
        var result: [TrashEntry] = []
        for entry in try entries(in: trashURL) {
            let infoURL = entry.url.appending(path: Self.trashInfoFileName)
            if entry.isDirectory,
               let data = try? Data(contentsOf: infoURL),
               let info = try? Self.jsonDecoder.decode(TrashInfo.self, from: data),
               let item = try entries(in: entry.url).first {
                result.append(TrashEntry(
                    itemURL: item.url, containerURL: entry.url, name: item.name,
                    originalPath: info.originalPath, deletedAt: info.deletedAt, isFolder: item.isDirectory
                ))
            } else {
                // Ohne Begleitinfo, z. B. im Finder direkt hineingezogen.
                // Notizen gehen beim Wiederherstellen in die Inbox, Ordner nach oben.
                let original = entry.isDirectory
                    ? entry.name
                    : "\(VaultLayout.inboxFolderName)/\(entry.name)"
                result.append(TrashEntry(
                    itemURL: entry.url, containerURL: nil, name: entry.name,
                    originalPath: original, deletedAt: entry.modified, isFolder: entry.isDirectory
                ))
            }
        }
        return result.sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Legt das Element an seinen ursprünglichen Ort zurück. Fehlt der Ordner
    /// inzwischen, wird er neu angelegt. Ist der Name belegt, gibt es eine Nummer.
    @discardableResult
    public func restore(_ entry: TrashEntry) throws -> URL {
        let original = root.appending(path: entry.originalPath)
        let folder = original.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let parts = entry.isFolder
            ? (base: original.lastPathComponent, pathExtension: nil)
            : FileNaming.split(original.lastPathComponent)
        let target = FileNaming.uniqueURL(in: folder, baseName: parts.base, pathExtension: parts.pathExtension)

        try Coordinated.move(from: entry.itemURL, to: target)
        if let container = entry.containerURL {
            try? FileManager.default.removeItem(at: container)
        }
        return target
    }

    public func deletePermanently(_ entry: TrashEntry) throws {
        try Coordinated.delete(entry.itemURL)
        if let container = entry.containerURL {
            try? FileManager.default.removeItem(at: container)
        }
    }

    /// Entfernt endgültig, was länger als 30 Tage im Papierkorb liegt.
    /// Leert «Zuletzt gelöscht» ganz. Liefert die Anzahl gelöschter Einträge.
    @discardableResult
    public func emptyTrash() throws -> Int {
        let entries = try trashEntries()
        for entry in entries { try deletePermanently(entry) }
        return entries.count
    }

    public func purgeTrash(now: Date = .now) throws {
        let cutoff = now.addingTimeInterval(-Double(Self.trashRetentionDays) * 24 * 60 * 60)
        for entry in try trashEntries() where entry.deletedAt < cutoff {
            try deletePermanently(entry)
        }
    }

    private static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
