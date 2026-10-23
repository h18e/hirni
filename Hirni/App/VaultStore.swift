import Foundation
import HirniKit
import Observation
import os

let vaultLog = Logger(subsystem: "ch.hebera.hirni", category: "vault")

/// Was in der Seitenleiste ausgewählt ist.
enum SidebarItem: Hashable {
    case inbox
    case folder(URL)
    case trash
}

/// Zentraler Zustand der App: Ordnerbaum, Notizliste, Auswahl.
///
/// Alle Dateioperationen laufen über `HirniKit.Vault` in einem Hintergrund-Task.
/// Danach wird neu eingelesen. Änderungen von anderen Geräten oder Programmen
/// meldet der `VaultMonitor`, der dann ebenfalls `reload()` auslöst.
@Observable
final class VaultStore {
    let vault: Vault

    private(set) var folders: [FolderNode] = []
    private(set) var notes: [NoteSummary] = []
    private(set) var trash: [TrashEntry] = []

    var sidebarSelection: SidebarItem? = .inbox {
        didSet {
            guard oldValue != sidebarSelection else { return }
            selectedNote = nil
            notes = []
            Task { await reload() }
        }
    }
    var selectedNote: URL?

    /// Eben angelegte Notiz: Der Editor setzt dann den Fokus auf den Titel.
    var justCreatedNote: URL?

    var errorMessage: String?

    /// Zählt jedes Neueinlesen hoch. Der Editor prüft dann, ob seine Datei von
    /// aussen geändert wurde.
    private(set) var revision = 0

    private var monitor: VaultMonitor?

    init(vault: Vault) {
        self.vault = vault
    }

    var currentFolderURL: URL? {
        switch sidebarSelection {
        case .inbox, nil: vault.inboxURL
        case .folder(let url): url
        case .trash: nil
        }
    }

    var currentTitle: String {
        switch sidebarSelection {
        case .inbox, nil: VaultLayout.inboxFolderName
        case .folder(let url): url.lastPathComponent
        case .trash: "Zuletzt gelöscht"
        }
    }

    func start() async {
        guard monitor == nil else { return }
        let monitor = VaultMonitor { [weak self] in
            Task { await self?.reload() }
        }
        monitor.start()
        self.monitor = monitor
        await perform { try $0.purgeTrash() }
        await reload()
    }

    func reload() async {
        let started = ContinuousClock.now
        defer { vaultLog.debug("reload: \(ContinuousClock.now - started, privacy: .public)") }
        let vault = vault
        let folderURL = currentFolderURL
        let showsTrash = sidebarSelection == .trash
        let result = await Task.detached {
            (
                folders: Result { try vault.folderTree() },
                notes: Result { try folderURL.map { try vault.notes(in: $0) } ?? [] },
                trash: Result { showsTrash ? try vault.trashEntries() : [] }
            )
        }.value

        if case .success(let folders) = result.folders { self.folders = folders }
        if case .success(let trash) = result.trash { self.trash = trash }
        switch result.notes {
        case .success(let notes):
            self.notes = notes
        case .failure:
            // Der gewählte Ordner existiert nicht mehr (z. B. auf dem anderen
            // Gerät gelöscht oder umbenannt): zurück zur Inbox.
            if case .folder = sidebarSelection { sidebarSelection = .inbox }
        }
        revision += 1
    }

    // MARK: - Notizen

    func newNote() async {
        if sidebarSelection == .trash { sidebarSelection = .inbox }
        let folder = currentFolderURL ?? vault.inboxURL
        guard let url = await perform({ try $0.createNote(in: folder) }) else { return }
        await reload()
        justCreatedNote = url
        selectedNote = url
    }

    func read(_ url: URL) async -> String? {
        await perform { try $0.readNote(at: url) }
    }

    /// Liefert das neue Änderungsdatum der Datei, oder `nil` bei einem Fehler.
    func write(_ text: String, to url: URL) async -> Date? {
        let modified = await perform { try $0.writeNote(text, to: url) }
        if modified != nil { await reload() } // Vorschau und Reihenfolge in der Liste
        return modified
    }

    func modificationDate(of url: URL) async -> Date? {
        let vault = vault
        return await Task.detached { vault.modificationDate(of: url) }.value
    }

    /// Benennt um. Die Auswahl passt der Editor selbst an, weil er die Datei
    /// gerade offen hat.
    func renameNote(_ url: URL, to title: String) async -> URL? {
        guard let newURL = await perform({ try $0.renameNote(at: url, to: title) }) else { return nil }
        await reload()
        return newURL
    }

    func deleteNote(_ url: URL) async {
        guard await perform({ try $0.moveToTrash(url) }) != nil else { return }
        if selectedNote == url { selectedNote = nil }
        await reload()
    }

    // MARK: - Ordner

    func newFolder(in parent: URL?, name: String) async {
        let parent = parent ?? vault.root
        guard let url = await perform({ try $0.createFolder(in: parent, name: name) }) else { return }
        await reload()
        sidebarSelection = .folder(url)
    }

    func renameFolder(_ url: URL, to name: String) async {
        guard let newURL = await perform({ try $0.renameFolder(at: url, to: name) }) else { return }
        if case .folder(let selected) = sidebarSelection, selected.isInside(url) {
            let suffix = selected.pathComponents.dropFirst(url.pathComponents.count)
            sidebarSelection = .folder(suffix.reduce(newURL) { $0.appending(path: $1, directoryHint: .isDirectory) })
        }
        await reload()
    }

    func deleteFolder(_ url: URL) async {
        guard await perform({ try $0.moveToTrash(url) }) != nil else { return }
        if case .folder(let selected) = sidebarSelection, selected.isInside(url) {
            sidebarSelection = .inbox
        }
        await reload()
    }

    // MARK: - Zuletzt gelöscht

    func restore(_ entry: TrashEntry) async {
        await perform { try $0.restore(entry) }
        await reload()
    }

    func deletePermanently(_ entry: TrashEntry) async {
        await perform { try $0.deletePermanently(entry) }
        await reload()
    }

    // MARK: - Hilfen

    /// Führt eine Dateioperation im Hintergrund aus. Fehler erscheinen als Hinweis.
    @discardableResult
    private func perform<T: Sendable>(_ work: @escaping @Sendable (Vault) throws -> T) async -> T? {
        let vault = vault
        let started = ContinuousClock.now
        defer { vaultLog.debug("perform: \(ContinuousClock.now - started, privacy: .public)") }
        do {
            return try await Task.detached { try work(vault) }.value
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

extension URL {
    /// `true`, wenn diese URL gleich `folder` ist oder darin liegt.
    func isInside(_ folder: URL) -> Bool {
        let parts = standardizedFileURL.pathComponents
        let folderParts = folder.standardizedFileURL.pathComponents
        return parts.count >= folderParts.count && Array(parts.prefix(folderParts.count)) == folderParts
    }
}
