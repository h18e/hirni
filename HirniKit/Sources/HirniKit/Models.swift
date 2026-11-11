import Foundation

/// Ein Ordner im hirni-Ordnerbaum (ohne Systemordner und ohne Inbox).
public struct FolderNode: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public var children: [FolderNode]

    /// Für `OutlineGroup`/`List(children:)`: `nil` heisst «kein Aufklapp-Pfeil».
    public var childrenOrNil: [FolderNode]? { children.isEmpty ? nil : children }

    public init(url: URL, name: String, children: [FolderNode] = []) {
        self.url = url
        self.name = name
        self.children = children
    }
}

/// Eine Notiz, wie sie in der Notizliste erscheint.
public struct NoteSummary: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let title: String
    public let modified: Date
    /// Erstellungsdatum der Datei.
    public let created: Date
    public let preview: String
    /// `false`, solange iCloud nur einen Platzhalter auf diesem Gerät hat.
    public let isDownloaded: Bool
    /// `angepinnt: true` im YAML-Kopf. Angepinnte Notizen stehen oben.
    public let isPinned: Bool
    /// Eine Datenbank (`.hirnidb.md`) statt einer Notiz.
    public var isDatabase: Bool { Vault.isDatabase(url) }

    public init(url: URL, title: String, modified: Date, created: Date? = nil, preview: String, isDownloaded: Bool, isPinned: Bool = false) {
        self.url = url
        self.title = title
        self.modified = modified
        self.created = created ?? modified
        self.preview = preview
        self.isDownloaded = isDownloaded
        self.isPinned = isPinned
    }
}

/// Ein Eintrag in «Zuletzt gelöscht».
public struct TrashEntry: Identifiable, Hashable, Sendable {
    public var id: URL { itemURL }
    /// Die gelöschte Datei bzw. der gelöschte Ordner selbst.
    public let itemURL: URL
    /// Der Hülle-Ordner `_Zuletzt gelöscht/<id>/`, oder `nil`, wenn das Element
    /// direkt im Papierkorb liegt (z. B. per Finder hineingezogen).
    public let containerURL: URL?
    public let name: String
    /// Pfad relativ zum hirni-Ordner, an dem das Element vor dem Löschen lag.
    public let originalPath: String
    public let deletedAt: Date
    public let isFolder: Bool
}

/// Reihenfolge der Notizliste. Angepinnte Notizen stehen immer oben.
public struct NoteSort: Equatable, Sendable {
    public enum Field: String, CaseIterable, Sendable {
        case modified = "geändert"
        case created = "erstellt"
        case title = "titel"
    }

    public var field: Field
    /// Titel: A–Z. Datum: älteste zuerst.
    public var ascending: Bool

    public init(field: Field = .modified, ascending: Bool = false) {
        self.field = field
        self.ascending = ascending
    }

    /// Neueste zuerst bzw. A–Z, wie man es beim Wechsel erwartet.
    public static func natural(_ field: Field) -> NoteSort {
        NoteSort(field: field, ascending: field == .title)
    }

    public func apply(_ notes: [NoteSummary]) -> [NoteSummary] {
        notes.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            let order: ComparisonResult = switch field {
            case .title: a.title.localizedStandardCompare(b.title)
            case .modified: Self.compare(a.modified, b.modified)
            case .created: Self.compare(a.created, b.created)
            }
            if order == .orderedSame {
                // Gleiche Werte: immer nach Titel, damit nichts springt.
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    private static func compare(_ a: Date, _ b: Date) -> ComparisonResult {
        a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
    }
}
