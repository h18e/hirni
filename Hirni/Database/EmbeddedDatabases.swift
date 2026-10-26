import HirniKit
import Observation
import SwiftUI

/// Die in einer Notiz eingebetteten Datenbanken (`hirni-db`-Blöcke).
///
/// Pro Block ein eigenes `DatabaseDocument`, das wie die volle Ansicht lädt,
/// speichert und Änderungen von aussen übernimmt. Der Editor fragt hier nach
/// der Höhe, die er unter dem Block frei lassen soll.
@Observable
final class EmbeddedDatabases {
    let store: VaultStore
    /// Die Notiz, in der die Blöcke stehen (für Namen ohne Pfad).
    @ObservationIgnored var note: URL?
    /// Höhe oder Inhalt hat sich geändert: Lücken neu berechnen.
    @ObservationIgnored var onLayoutChange: () -> Void = {}

    /// Eintrag, dessen Formular die Notiz gerade zeigt.
    var editingRow: EditingRow?
    /// Datenbank, deren Felder die Notiz gerade bearbeiten lässt.
    var editingFields: EditingFields?

    struct EditingFields: Identifiable {
        let document: DatabaseDocument
        var id: URL { document.url }
    }

    struct EditingRow: Identifiable {
        let document: DatabaseDocument
        let rowID: String
        var id: String { rowID }
    }

    enum State {
        case loading
        case missing
        case loaded(DatabaseDocument)
    }

    private(set) var states: [String: State] = [:]

    init(store: VaultStore) {
        self.store = store
    }

    static func key(_ embed: DatabaseEmbed) -> String {
        "\(embed.database.lowercased())|\(embed.view ?? "")"
    }

    func state(for embed: DatabaseEmbed) -> State {
        states[Self.key(embed)] ?? .loading
    }

    /// Lädt die Datenbank des Blocks, falls noch nicht geschehen.
    func prepare(_ embed: DatabaseEmbed) {
        let key = Self.key(embed)
        guard states[key] == nil else { return }
        states[key] = .loading
        Task { await load(embed) }
    }

    private func load(_ embed: DatabaseEmbed) async {
        let key = Self.key(embed)
        guard let note, let url = await resolve(embed.database, from: note) else {
            states[key] = .missing
            onLayoutChange()
            return
        }
        let document = DatabaseDocument(store: store, url: url, isEmbedded: true)
        await document.load()
        if let view = embed.view, document.database.views.contains(where: { $0.name == view }) {
            document.selectView(view)
        }
        states[key] = document.isLoaded ? .loaded(document) : .missing
        onLayoutChange()
    }

    private func resolve(_ reference: String, from note: URL) async -> URL? {
        let vault = store.vault
        return await Task.detached { vault.resolveDatabase(reference, from: note) }.value
    }

    /// Nach Änderungen im hirni-Ordner: Datenbanken neu laden, fehlende neu suchen.
    func refresh() async {
        for (key, state) in states {
            switch state {
            case .loaded(let document):
                await document.reloadIfChangedElsewhere()
            case .missing:
                states[key] = nil   // beim nächsten Zeichnen neu suchen
            case .loading:
                break
            }
        }
        onLayoutChange()
    }

    /// Speichert alles und gibt die Dokumente frei (Notiz wird geschlossen).
    func closeAll() async {
        for case .loaded(let document) in states.values { await document.close() }
        states = [:]
    }

    // MARK: - Höhe

    /// Platz unter dem Block: abhängig von Ansicht und Anzahl Einträge.
    func height(for embed: DatabaseEmbed) -> CGFloat {
        prepare(embed)
        switch state(for: embed) {
        case .loading: return Self.headerHeight + 80
        case .missing: return Self.headerHeight + 60
        case .loaded(let document):
            switch document.currentView.kind {
            case .chart: return Self.headerHeight + 370
            case .calendar:
                #if os(iOS)
                return Self.headerHeight + 470
                #else
                return Self.headerHeight + 640
                #endif
            case .table:
                let rows = document.result.rows.count
                if rows == 0 { return Self.headerHeight + 60 }
                var height = Self.headerHeight + DatabaseGrid.embeddedHeight(
                    rows: min(rows, Self.maxRows),
                    hasFooter: !(document.currentView.aggregates ?? [:]).isEmpty
                )
                if rows > Self.maxRows { height += 32 }
                return height
            }
        }
    }

    static let headerHeight: CGFloat = 44
    static let maxRows = 8
}
