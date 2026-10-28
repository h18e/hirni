import Foundation

/// Etwas, das aus einer anderen App mit «Teilen» an Hirni geschickt wurde.
public struct SharedItem: Codable, Equatable, Sendable {
    public var title: String
    /// Text der Notiz (Text, Link …).
    public var text: String
    /// Dateinamen der Anhänge (Bilder, PDFs), im Ordner des Eintrags.
    public var files: [String]

    public init(title: String, text: String, files: [String] = []) {
        self.title = title
        self.text = text
        self.files = files
    }

    /// Vorschlag für den Titel: erste Zeile, gekürzt.
    public static func suggestedTitle(text: String, url: URL?) -> String {
        let firstLine = text.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if !firstLine.isEmpty, !firstLine.hasPrefix("http") {
            return firstLine.count > 60 ? String(firstLine.prefix(60)).trimmingCharacters(in: .whitespaces) + "…" : firstLine
        }
        if let host = url?.host() {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return "Geteilt"
    }
}

extension Vault {
    /// Legt aus geteiltem Inhalt eine Notiz in der Inbox an: zuerst der Text,
    /// darunter die Anhänge (je auf eigener Zeile).
    @discardableResult
    public func importShared(_ item: SharedItem, files: [URL]) throws -> URL {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = try createNote(in: inboxURL, title: title.isEmpty ? "Geteilt" : title, text: "")
        let embeds = try files.map { try importAttachment(copying: $0, for: note) }
        let text = [item.text.trimmingCharacters(in: .whitespacesAndNewlines), embeds.joined(separator: "\n")]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        try writeNote(text + "\n", to: note)
        return note
    }
}

/// Warteschlange für geteilte Inhalte, wenn die Erweiterung den Hirni-Ordner
/// nicht direkt erreicht (z. B. iCloud gerade nicht verfügbar, Simulator).
/// Pro Eintrag ein Ordner mit `eintrag.json` und den Anhängen; die App holt
/// sie beim Start in die Inbox.
public enum SharedInbox {
    static let itemFile = "eintrag.json"

    /// Legt einen Eintrag in `queue` ab.
    public static func enqueue(_ item: SharedItem, files: [URL], in queue: URL) throws {
        let folder = queue.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var stored = item
        stored.files = []
        for file in files {
            let target = folder.appending(path: file.lastPathComponent)
            try FileManager.default.copyItem(at: file, to: target)
            stored.files.append(target.lastPathComponent)
        }
        try JSONEncoder().encode(stored).write(to: folder.appending(path: itemFile))
    }

    /// Holt alle wartenden Einträge in die Inbox und räumt die Warteschlange auf.
    /// Liefert die neuen Notizen.
    @discardableResult
    public static func importPending(from queue: URL, into vault: Vault) -> [URL] {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: queue, includingPropertiesForKeys: [.creationDateKey]) else { return [] }
        let sorted = folders.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
        var notes: [URL] = []
        for folder in sorted {
            guard let data = try? Data(contentsOf: folder.appending(path: itemFile)),
                  let item = try? JSONDecoder().decode(SharedItem.self, from: data),
                  let note = try? vault.importShared(item, files: item.files.map { folder.appending(path: $0) })
            else { continue }
            notes.append(note)
            try? FileManager.default.removeItem(at: folder)
        }
        return notes
    }
}
