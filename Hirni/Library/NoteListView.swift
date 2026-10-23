import HirniKit
import SwiftUI

struct NoteListView: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedNote) {
            ForEach(store.notes) { note in
                NoteRow(note: note)
                    .tag(note.url)
                    .swipeActions(edge: .trailing) {
                        Button("Löschen", systemImage: "trash", role: .destructive) {
                            Task { await store.deleteNote(note.url) }
                        }
                    }
                    .contextMenu {
                        Button("Löschen", systemImage: "trash", role: .destructive) {
                            Task { await store.deleteNote(note.url) }
                        }
                    }
            }
        }
        #if os(macOS)
        .onDeleteCommand {
            if let url = store.selectedNote { Task { await store.deleteNote(url) } }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        #endif
        .overlay {
            if store.notes.isEmpty {
                ContentUnavailableView(
                    "Keine Notizen",
                    systemImage: "note.text",
                    description: Text("Mit dem Stift oben eine neue Notiz anlegen.")
                )
            }
        }
        .navigationTitle(store.currentTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Neue Notiz", systemImage: "square.and.pencil") {
                    Task { await store.newNote() }
                }
                .keyboardShortcut("n")
            }
        }
        .refreshable { await store.reload() }
    }
}

private struct NoteRow: View {
    let note: NoteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title)
                .font(.headline)
                .lineLimit(1)
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
