import HirniKit
import SwiftUI

struct TrashListView: View {
    @Environment(VaultStore.self) private var store
    @State private var pendingDeletion: TrashEntry?

    var body: some View {
        List {
            Section {
                ForEach(store.trash) { entry in
                    TrashRow(entry: entry)
                        .swipeActions(edge: .leading) {
                            Button("Wiederherstellen", systemImage: "arrow.uturn.backward") {
                                Task { await store.restore(entry) }
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Endgültig löschen", systemImage: "trash.slash", role: .destructive) {
                                pendingDeletion = entry
                            }
                        }
                        .contextMenu {
                            Button("Wiederherstellen", systemImage: "arrow.uturn.backward") {
                                Task { await store.restore(entry) }
                            }
                            Button("Endgültig löschen", systemImage: "trash.slash", role: .destructive) {
                                pendingDeletion = entry
                            }
                        }
                }
            } footer: {
                if !store.trash.isEmpty {
                    Text("Wird nach \(Vault.trashRetentionDays) Tagen automatisch endgültig gelöscht.")
                }
            }
        }
        .overlay {
            if store.trash.isEmpty {
                ContentUnavailableView("Nichts gelöscht", systemImage: "trash")
            }
        }
        .navigationTitle("Zuletzt gelöscht")
        .confirmationDialog(
            "«\(pendingDeletion?.name ?? "")» endgültig löschen?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { entry in
            Button("Endgültig löschen", role: .destructive) {
                Task { await store.deletePermanently(entry) }
            }
        } message: { _ in
            Text("Das lässt sich nicht rückgängig machen.")
        }
    }
}

private struct TrashRow: View {
    let entry: TrashEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: entry.isFolder ? "folder" : "note.text")
                .font(.headline)
                .lineLimit(1)
            Text("aus \(origin) · gelöscht \(entry.deletedAt.formatted(.relative(presentation: .named)))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        entry.isFolder ? entry.name : Vault.title(of: entry.itemURL)
    }

    private var origin: String {
        let folder = (entry.originalPath as NSString).deletingLastPathComponent
        return folder.isEmpty ? "hirni" : folder
    }
}
