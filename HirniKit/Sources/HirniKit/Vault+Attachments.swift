import Foundation

/// Anhänge liegen im Ordner `_Anhänge` neben der Notiz und werden mit einem
/// relativen Pfad eingebettet: `![](_Anhänge/foto.jpg)`.
extension Vault {
    public func attachmentsFolder(for note: URL) -> URL {
        note.deletingLastPathComponent()
            .appending(path: VaultLayout.attachmentsFolderName, directoryHint: .isDirectory)
    }

    /// Kopiert eine Datei (aus «Dateien», Finder oder per Drag'n'Drop) als
    /// Anhang zur Notiz und liefert den Markdown-Text zum Einfügen.
    /// HEIC-Fotos werden dabei in JPEG umgewandelt.
    public func importAttachment(copying source: URL, for note: URL) throws -> String {
        let ext = source.pathExtension.lowercased()
        let baseName = source.deletingPathExtension().lastPathComponent
        if ext == "heic" || ext == "heif" {
            let data = try Coordinated.read(source) { try Data(contentsOf: $0) }
            if let jpeg = ImageEncoding.jpeg(from: data) {
                return try importAttachment(data: jpeg, fileExtension: "jpg", baseName: baseName, for: note)
            }
        }

        let target = try newAttachmentURL(baseName: baseName, fileExtension: ext, for: note)
        let data = try Coordinated.read(source) { try Data(contentsOf: $0) }
        try Coordinated.write(target, options: .forReplacing) { try data.write(to: $0, options: .withoutOverwriting) }
        return AttachmentLinks.markdown(for: relativeAttachmentPath(target))
    }

    /// Speichert Bilddaten (Foto-Mediathek, Kamera) als Anhang.
    public func importAttachment(data: Data, fileExtension: String, baseName: String, for note: URL) throws -> String {
        let target = try newAttachmentURL(baseName: baseName, fileExtension: fileExtension, for: note)
        try Coordinated.write(target, options: .forReplacing) { try data.write(to: $0, options: .withoutOverwriting) }
        return AttachmentLinks.markdown(for: relativeAttachmentPath(target))
    }

    /// Die Datei hinter einem eingebetteten Pfad, oder `nil`, wenn der Pfad aus
    /// dem hirni-Ordner hinausführt oder eine Web-Adresse ist.
    public func resolveAttachment(_ path: String, for note: URL) -> URL? {
        guard !path.contains("://"), !path.hasPrefix("/") else { return nil }
        let url = note.deletingLastPathComponent().appending(path: path).standardizedFileURL
        return contains(url) ? url : nil
    }

    // MARK: - Verschieben

    /// Nimmt beim Verschieben einer Notiz ihre Anhänge mit. Wird ein Anhang
    /// noch von einer anderen Notiz im alten Ordner verwendet, wird er kopiert
    /// statt verschoben. Ändert sich ein Dateiname (weil er am Ziel schon
    /// existiert), wird der Verweis im Text angepasst.
    func moveAttachments(ofNote noteText: String, from sourceNote: URL, toFolder targetFolder: URL) throws -> String {
        let sourceFolder = sourceNote.deletingLastPathComponent()
        let prefix = VaultLayout.attachmentsFolderName + "/"
        let embeds = AttachmentLinks.embeds(in: noteText).filter { $0.path.hasPrefix(prefix) }
        guard !embeds.isEmpty else { return noteText }

        let otherTexts = try notes(in: sourceFolder)
            .filter { $0.url.standardizedFileURL != sourceNote.standardizedFileURL }
            .compactMap { try? readNote(at: $0.url) }
        let fileManager = FileManager.default
        var renamed: [String: String] = [:] // alter Pfad → neuer Pfad

        for path in Set(embeds.map(\.path)) {
            let source = sourceFolder.appending(path: path)
            guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            let targetAttachments = targetFolder.appending(path: VaultLayout.attachmentsFolderName, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: targetAttachments, withIntermediateDirectories: true)
            let target = FileNaming.uniqueURL(
                in: targetAttachments,
                baseName: source.deletingPathExtension().lastPathComponent,
                pathExtension: source.pathExtension.isEmpty ? nil : source.pathExtension,
                separator: "-"
            )
            let usedElsewhere = otherTexts.contains { text in
                AttachmentLinks.embeds(in: text).contains { $0.path == path }
            }
            if usedElsewhere {
                let data = try Coordinated.read(source) { try Data(contentsOf: $0) }
                try Coordinated.write(target, options: .forReplacing) { try data.write(to: $0) }
            } else {
                try Coordinated.move(from: source, to: target)
            }
            let newPath = prefix + target.lastPathComponent
            if newPath != path { renamed[path] = newPath }
        }

        guard !renamed.isEmpty else { return noteText }
        let updated = NSMutableString(string: noteText)
        for embed in embeds.reversed() {
            if let newPath = renamed[embed.path] {
                updated.replaceCharacters(in: embed.range, with: AttachmentLinks.markdown(for: newPath, altText: embed.altText))
            }
        }
        return updated as String
    }

    // MARK: - Hilfen

    private func newAttachmentURL(baseName: String, fileExtension: String, for note: URL) throws -> URL {
        let folder = attachmentsFolder(for: note)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return FileNaming.uniqueURL(
            in: folder,
            baseName: Self.attachmentBaseName(baseName),
            pathExtension: fileExtension.isEmpty ? nil : fileExtension.lowercased(),
            separator: "-"
        )
    }

    /// Dateinamen ohne Leerzeichen: Dann bleibt der Markdown-Verweis lesbar
    /// und funktioniert in jedem Programm.
    static func attachmentBaseName(_ name: String) -> String {
        FileNaming.sanitized(name)
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }

    private func relativeAttachmentPath(_ url: URL) -> String {
        VaultLayout.attachmentsFolderName + "/" + url.lastPathComponent
    }
}
