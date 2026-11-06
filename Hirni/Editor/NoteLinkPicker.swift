import HirniKit
import SwiftUI

/// Auswahl der Zielnotiz für einen Link, mit Suche nach Titel und Ordner.
struct NoteLinkPicker: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Die offene Notiz: ein Link auf sich selbst ergibt keinen Sinn.
    let excluding: URL?
    let select: (NoteLink.Target) -> Void
    @State private var targets: [NoteLink.Target] = []
    @State private var query = ""

    private var filtered: [NoteLink.Target] {
        let words = query.lowercased().split(separator: " ")
        return targets.filter { target in
            let text = (target.title + " " + target.folder).lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { target in
                Button {
                    select(target)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.title).foregroundStyle(.primary)
                        if !target.folder.isEmpty {
                            Text(target.folder).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if filtered.isEmpty, !targets.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, prompt: "Notiz suchen")
            .navigationTitle("Link auf Notiz")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .task { targets = await store.linkTargets(excluding: excluding) }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 420)
        #endif
    }
}
