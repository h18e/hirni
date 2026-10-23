import HirniKit
import SwiftUI

/// «Verschieben nach …»: Auswahl des Zielordners für eine Notiz oder einen Ordner.
struct FolderPickerView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Was verschoben wird.
    let item: URL

    private var isFolder: Bool {
        (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private var currentParent: URL {
        item.deletingLastPathComponent().standardizedFileURL
    }

    var body: some View {
        NavigationStack {
            List {
                if isFolder {
                    destination("Oberste Ebene", systemImage: "square.stack", url: store.vault.root)
                } else {
                    destination(VaultLayout.inboxFolderName, systemImage: "tray", url: store.vault.inboxURL)
                }
                Section("Ordner") {
                    OutlineGroup(store.folders, children: \.childrenOrNil) { folder in
                        destination(folder.name, systemImage: "folder", url: folder.url)
                    }
                }
            }
            .navigationTitle("«\(itemTitle)» verschieben")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
    }

    private var itemTitle: String {
        isFolder ? item.lastPathComponent : Vault.title(of: item)
    }

    private func destination(_ title: String, systemImage: String, url: URL) -> some View {
        let isCurrent = url.standardizedFileURL == currentParent
        // Ein Ordner kann nicht in sich selbst oder einen Unterordner wandern.
        let isInvalid = isFolder && url.isInside(item)
        return Button {
            Task {
                await store.move(item, to: url)
                dismiss()
            }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(isCurrent || isInvalid ? .secondary : .primary)
                Spacer()
                if isCurrent {
                    Text("aktuell").foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isCurrent || isInvalid)
    }
}
