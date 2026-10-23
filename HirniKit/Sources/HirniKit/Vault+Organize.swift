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
        let target = isFolder
            ? FileNaming.uniqueURL(in: folder, baseName: url.lastPathComponent, pathExtension: nil)
            : FileNaming.uniqueURL(
                in: folder, baseName: url.deletingPathExtension().lastPathComponent, pathExtension: url.pathExtension
            )
        try Coordinated.move(from: url, to: target)
        return target
    }

    /// Legt «Titel Kopie» im selben Ordner an. Die Kopie ist nicht angepinnt.
    public func duplicateNote(at url: URL) throws -> URL {
        let text = Frontmatter.setting(Frontmatter.pinnedKey, to: nil, in: try readNote(at: url))
        return try createNote(
            in: url.deletingLastPathComponent(), title: "\(Self.title(of: url)) Kopie", text: text
        )
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
