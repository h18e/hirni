import HirniKit
import SwiftUI

struct NoteListView: View {
    @Environment(VaultStore.self) private var store
    /// Notiz, für die gerade «Verschieben nach …» offen ist.
    @State private var moving: MovingItem?

    @State private var query = ""
    @State private var scope = SearchScope.everywhere
    @State private var hits: [SearchHit] = []

    enum SearchScope: Hashable {
        case everywhere
        case currentFolder
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedNote) {
            if isSearching {
                ForEach(hits) { hit in
                    SearchResultRow(hit: hit)
                        .tag(hit.url)
                }
            } else {
                noteRows
            }
        }
        #if os(macOS)
        .onDeleteCommand {
            if let url = store.selectedNote, !isSearching { Task { await store.deleteNote(url) } }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        #endif
        .overlay { emptyState }
        .navigationTitle(store.currentTitle)
        .searchable(text: $query, prompt: "Suchen")
        .searchScopes($scope, activation: .onSearchPresentation) {
            Text("Überall").tag(SearchScope.everywhere)
            if store.currentFolderURL != nil {
                Text("In «\(store.currentTitle)»").tag(SearchScope.currentFolder)
            }
        }
        // Kurz warten, bis fertig getippt ist, dann suchen.
        .task(id: SearchRequest(query: query, scope: scope, revision: store.revision)) {
            guard isSearching else { return hits = [] }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            hits = await store.search(query, inCurrentFolder: scope == .currentFolder)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Neue Datenbank", systemImage: "tablecells.badge.ellipsis") {
                    Task { await store.newDatabase() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Neue Notiz", systemImage: "square.and.pencil") {
                    Task { await store.newNote() }
                }
                .keyboardShortcut("n")
            }
        }
        .refreshable { await store.reload() }
        .sheet(item: $moving) { item in
            FolderPickerView(item: item.url)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isSearching {
            if hits.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        } else if store.notes.isEmpty {
            ContentUnavailableView(
                "Keine Notizen",
                systemImage: "note.text",
                description: Text("Mit dem Stift oben eine neue Notiz anlegen.")
            )
        }
    }

    private var noteRows: some View {
        ForEach(store.notes) { note in
            NoteRow(note: note, hasConflict: store.hasConflict(note.url))
                .tag(note.url)
                .draggable(VaultItemTransfer(url: note.url)) {
                    Label(note.title, systemImage: "note.text")
                }
                .swipeActions(edge: .leading) {
                    Button("Verschieben", systemImage: "folder") {
                        moving = MovingItem(url: note.url)
                    }
                    .tint(.indigo)
                    pinButton(for: note)
                        .tint(.orange)
                }
                .swipeActions(edge: .trailing) {
                    Button("Löschen", systemImage: "trash", role: .destructive) {
                        Task { await store.deleteNote(note.url) }
                    }
                }
                .contextMenu { menu(for: note) }
        }
    }

    @ViewBuilder
    private func menu(for note: NoteSummary) -> some View {
        pinButton(for: note)
        Button("Duplizieren", systemImage: "plus.square.on.square") {
            Task { await store.duplicateNote(note.url) }
        }
        Button("Verschieben nach …", systemImage: "folder") {
            moving = MovingItem(url: note.url)
        }
        Divider()
        Button("Löschen", systemImage: "trash", role: .destructive) {
            Task { await store.deleteNote(note.url) }
        }
    }

    private func pinButton(for note: NoteSummary) -> some View {
        Button(
            note.isPinned ? "Lösen" : "Anpinnen",
            systemImage: note.isPinned ? "pin.slash" : "pin"
        ) {
            Task { await store.setPinned(!note.isPinned, note: note.url) }
        }
    }
}

/// Löst eine neue Suche aus, wenn sich Eingabe, Bereich oder Dateien ändern.
private struct SearchRequest: Equatable {
    let query: String
    let scope: NoteListView.SearchScope
    let revision: Int
}

/// Für `.sheet(item:)`: eine URL, die verschoben werden soll.
struct MovingItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct NoteRow: View {
    let note: NoteSummary
    let hasConflict: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if note.isDatabase {
                    Image(systemName: "tablecells")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Datenbank")
                }
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Angepinnt")
                }
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                if hasConflict {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Mehrere Fassungen")
                }
            }
            HStack(spacing: 6) {
                Text(note.modified, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
                if !note.isDownloaded {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Wird geladen")
                }
                Text(note.preview)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}
