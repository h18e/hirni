import Foundation

/// Kleine lokale Kopie dessen, was Hirni beim Start zuerst zeigt: der
/// Ordnerbaum und je Ordner die Notizliste (Titel, Daten, Vorschauzeile).
/// Keine Notizinhalte und keine Anhänge, darum bleibt sie klein. Sie liegt nur
/// auf diesem Gerät und wird bei jedem Neueinlesen nachgeführt; beim Start
/// erscheint sie sofort, bis iCloud bereit ist. Pfade relativ zum Hirni-Ordner.
public struct VaultSnapshot: Codable, Equatable, Sendable {
    public struct Folder: Codable, Equatable, Sendable {
        var path: String
        var name: String
        var children: [Folder]
    }

    public struct Note: Codable, Equatable, Sendable {
        var path: String
        var title: String
        var modified: Date
        var created: Date
        var preview: String
        var isPinned: Bool
    }

    static let currentVersion = 1
    var version = Self.currentVersion
    var folders: [Folder] = []
    /// Ordnerpfad → Notizen.
    var notes: [String: [Note]] = [:]

    public init() {}

    public var isEmpty: Bool { folders.isEmpty && notes.isEmpty }

    // MARK: - Nachführen

    public mutating func record(folders tree: [FolderNode], in vault: Vault) {
        func convert(_ node: FolderNode) -> Folder? {
            vault.relativePath(of: node.url).map { Folder(path: $0, name: node.name, children: node.children.compactMap(convert)) }
        }
        folders = tree.compactMap(convert)
        // Listen gelöschter Ordner fallen weg.
        var existing: Set<String> = [VaultLayout.inboxFolderName]
        func collect(_ folder: Folder) {
            existing.insert(folder.path)
            folder.children.forEach(collect)
        }
        folders.forEach(collect)
        notes = notes.filter { existing.contains($0.key) }
    }

    public mutating func record(notes list: [NoteSummary], in folder: URL, vault: Vault) {
        guard let key = vault.relativePath(of: folder) else { return }
        // Noch nicht geladene Notizen haben keine Vorschau: die alte behalten.
        let earlier = Dictionary((notes[key] ?? []).map { ($0.path, $0.preview) }, uniquingKeysWith: { a, _ in a })
        notes[key] = list.compactMap { note in
            vault.relativePath(of: note.url).map {
                Note(path: $0, title: note.title, modified: note.modified, created: note.created,
                     preview: note.isDownloaded ? note.preview : (earlier[$0] ?? note.preview), isPinned: note.isPinned)
            }
        }
    }

    // MARK: - Lesen

    /// Wie beim Einlesen des Ordners: Pfade mit aufgelösten Verknüpfungen,
    /// damit die gemerkten Adressen den frisch gelesenen gleichen.
    private func base(of vault: Vault) -> URL {
        guard let real = realpath(vault.root.path, nil) else { return vault.root }
        defer { free(real) }
        return URL(filePath: String(cString: real), directoryHint: .isDirectory)
    }

    public func folderNodes(in vault: Vault) -> [FolderNode] {
        let root = base(of: vault)
        func convert(_ folder: Folder) -> FolderNode {
            FolderNode(url: root.appending(path: folder.path, directoryHint: .isDirectory),
                       name: folder.name, children: folder.children.map(convert))
        }
        return folders.map(convert)
    }

    /// Die gemerkte Liste eines Ordners, `nil` wenn er noch nie angezeigt wurde.
    public func notes(in folder: URL, vault: Vault) -> [NoteSummary]? {
        guard let key = vault.relativePath(of: folder), let list = notes[key] else { return nil }
        let root = base(of: vault)
        return list.map {
            NoteSummary(url: root.appending(path: $0.path), title: $0.title, modified: $0.modified,
                        created: $0.created, preview: $0.preview, isDownloaded: true, isPinned: $0.isPinned)
        }
    }

    // MARK: - Datei

    /// Liest die Kopie; fehlt sie oder stammt sie aus einer älteren Version: leer.
    public static func load(from url: URL) -> VaultSnapshot {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(VaultSnapshot.self, from: data),
              snapshot.version == currentVersion
        else { return VaultSnapshot() }
        return snapshot
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
