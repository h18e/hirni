import Foundation

/// Schnellerfassung von aussen (Kurzbefehle, Siri, Widget).
extension Vault {
    /// Neue Notiz in der Inbox; Titel = erste Zeile des Texts.
    @discardableResult
    public func quickNote(_ text: String, title: String? = nil) throws -> URL {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try importShared(SharedItem(
            title: title?.isEmpty == false ? title! : SharedItem.suggestedTitle(text: text, url: nil),
            text: text
        ), files: [])
    }

    /// Hängt eine offene Pendenz (`- [ ] …`) an die Notiz «Pendenzen» in der
    /// Inbox an; gibt es sie nicht, wird sie angelegt.
    @discardableResult
    public func quickTask(_ text: String, noteTitle: String = "Pendenzen") throws -> URL {
        let line = "- [ ] " + text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let url = inboxURL.appending(path: FileNaming.sanitized(noteTitle) + "." + VaultLayout.noteExtension)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
            try writeNote(line + "\n", to: url)
            return url
        }
        var existing = try readNote(at: url)
        if !existing.isEmpty, !existing.hasSuffix("\n") { existing += "\n" }
        try writeNote(existing + line + "\n", to: url)
        return url
    }
}

/// Was das Widget zeigt: die offenen Pendenzen, fällige zuerst. Die App legt
/// es im gemeinsamen App-Gruppen-Ordner ab, das Widget liest nur.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var text: String
        public var note: String
        /// Pfad ab dem Hirni-Ordner, zum Öffnen.
        public var notePath: String
        /// `yyyy-MM-dd` oder `nil`.
        public var due: String?

        public init(id: String, text: String, note: String, notePath: String, due: String?) {
            self.id = id
            self.text = text
            self.note = note
            self.notePath = notePath
            self.due = due
        }

        public var dueDate: Date? { due.flatMap(TaskLine.parseDate) }
    }

    public static let fileName = "Widget.json"

    public var openCount: Int
    public var items: [Item]

    public init(openCount: Int = 0, items: [Item] = []) {
        self.openCount = openCount
        self.items = items
    }

    public static func make(tasks: [TaskItem], dueDates: TaskDueDates, in vault: Vault, limit: Int = 12) -> WidgetSnapshot {
        let open = tasks.filter { !$0.isDone }
        let items = open.enumerated().map { index, task in
            let key = task.dueKey(in: vault)
            return (index, Item(
                id: key,
                text: task.text,
                note: Vault.title(of: task.note),
                notePath: vault.relativePath(of: task.note) ?? task.note.lastPathComponent,
                due: dueDates.stichtage[key]
            ))
        }
        // Mit Stichtag zuerst (früheste oben), sonst Reihenfolge in den Notizen.
        let sorted = items.sorted { a, b in
            switch (a.1.due, b.1.due) {
            case let (x?, y?) where x != y: x < y
            case (_?, nil): true
            case (nil, _?): false
            default: a.0 < b.0
            }
        }
        return WidgetSnapshot(openCount: open.count, items: sorted.prefix(limit).map(\.1))
    }

    public static func load(from folder: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: folder.appending(path: fileName)) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func save(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: folder.appending(path: Self.fileName), options: .atomic)
    }
}
