import HirniKit
import SwiftUI

struct NoteListView: View {
    @Environment(VaultStore.self) private var store
    /// Notiz, für die gerade «Verschieben nach …» offen ist.
    @State private var moving: MovingItem?

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedNote) {
            ForEach(store.notes) { note in
                NoteRow(note: note)
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
        .sheet(item: $moving) { item in
            FolderPickerView(item: item.url)
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

/// Für `.sheet(item:)`: eine URL, die verschoben werden soll.
struct MovingItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct NoteRow: View {
    let note: NoteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Angepinnt")
                }
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
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
