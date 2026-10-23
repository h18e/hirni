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
    public let preview: String
    /// `false`, solange iCloud nur einen Platzhalter auf diesem Gerät hat.
    public let isDownloaded: Bool
    /// `angepinnt: true` im YAML-Kopf. Angepinnte Notizen stehen oben.
    public let isPinned: Bool

    public init(url: URL, title: String, modified: Date, preview: String, isDownloaded: Bool, isPinned: Bool = false) {
        self.url = url
        self.title = title
        self.modified = modified
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
