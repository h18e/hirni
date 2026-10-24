import Foundation

public enum VaultError: LocalizedError {
    case cannotMoveIntoItself

    public var errorDescription: String? {
        switch self {
        case .cannotMoveIntoItself: "Ein Ordner kann nicht in sich selbst verschoben werden."
        }
    }
}

/// Ordnen: verschieben, duplizieren, anpinnen.
extension Vault {
    /// Verschiebt eine Notiz oder einen Ordner nach `folder` und liefert die neue
    /// Adresse. Ist der Name dort belegt, gibt es eine Nummer.
    @discardableResult
    public func move(_ url: URL, to folder: URL) throws -> URL {
        if url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
            return url
        }
        if folder.isInside(url) { throw VaultError.cannotMoveIntoItself }

        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isFolder {
            // Ein Ordner nimmt seinen `_Anhänge`-Ordner automatisch mit.
            let target = FileNaming.uniqueURL(in: folder, baseName: url.lastPathComponent, pathExtension: nil)
            try Coordinated.move(from: url, to: target)
            return target
        }

        let parts = FileNaming.split(url.lastPathComponent)
        let target = FileNaming.uniqueURL(in: folder, baseName: parts.base, pathExtension: parts.pathExtension)
        let text = Self.isNote(name: url.lastPathComponent) ? try? readNote(at: url) : nil
        let updated = try text.map { try moveAttachments(ofNote: $0, from: url, toFolder: folder) }
        try Coordinated.move(from: url, to: target)
        if let text, let updated, updated != text {
            try writeNote(updated, to: target)
        }
        return target
    }

    /// Legt «Titel Kopie» im selben Ordner an. Die Kopie ist nicht angepinnt.
    public func duplicateNote(at url: URL) throws -> URL {
        let text = Frontmatter.setting(Frontmatter.pinnedKey, to: nil, in: try readNote(at: url))
        let title = "\(Self.title(of: url)) Kopie"
        guard Self.isDatabase(url) else {
            return try createNote(in: url.deletingLastPathComponent(), title: title, text: text)
        }
        let copy = FileNaming.uniqueURL(
            in: url.deletingLastPathComponent(),
            baseName: FileNaming.sanitized(title),
            pathExtension: String(VaultLayout.databaseSuffix.dropFirst())
        )
        try Coordinated.write(copy, options: .forReplacing) { try Data(text.utf8).write(to: $0, options: .withoutOverwriting) }
        return copy
    }

    /// Anpinnen ist keine inhaltliche Änderung: Das Änderungsdatum bleibt, damit
    /// die Notiz in der Liste nicht als «eben bearbeitet» erscheint.
    public func setPinned(_ pinned: Bool, note url: URL) throws {
        let text = try readNote(at: url)
        let updated = Frontmatter.setting(Frontmatter.pinnedKey, to: pinned ? "true" : nil, in: text)
        guard updated != text else { return }
        let modified = modificationDate(of: url)
        try Coordinated.write(url) { url in
            try Data(updated.utf8).write(to: url, options: .atomic)
            if let modified {
                try FileManager.default.setAttributes(
                    [.modificationDate: modified], ofItemAtPath: url.path(percentEncoded: false)
                )
            }
        }
    }
}

extension URL {
    /// `true`, wenn diese URL gleich `folder` ist oder darin liegt.
    public func isInside(_ folder: URL) -> Bool {
        let parts = standardizedFileURL.pathComponents
        let folderParts = folder.standardizedFileURL.pathComponents
        return parts.count >= folderParts.count && Array(parts.prefix(folderParts.count)) == folderParts
    }
}
