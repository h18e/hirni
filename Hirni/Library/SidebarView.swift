import HirniKit
import SwiftUI

struct SidebarView: View {
    @Environment(VaultStore.self) private var store

    @State private var prompt: FolderPrompt?
    @State private var folderName = ""

    var body: some View {
        @Bindable var store = store

        List(selection: $store.sidebarSelection) {
            Label(VaultLayout.inboxFolderName, systemImage: "tray")
                .tag(SidebarItem.inbox)

            Section("Ordner") {
                OutlineGroup(store.folders, children: \.childrenOrNil) { folder in
                    Label(folder.name, systemImage: "folder")
                        .tag(SidebarItem.folder(folder.url))
                        .contextMenu { folderMenu(for: folder) }
                }
            }

            Label("Zuletzt gelöscht", systemImage: "trash")
                .tag(SidebarItem.trash)
        }
        .navigationTitle("hirni")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        #endif
        .toolbar {
            ToolbarItem {
                Button("Neuer Ordner", systemImage: "folder.badge.plus") {
                    ask(.create(parent: nil))
                }
            }
        }
        .alert(prompt?.title ?? "", isPresented: promptIsPresented, presenting: prompt) { prompt in
            TextField("Name", text: $folderName)
            Button("Abbrechen", role: .cancel) {}
            Button(prompt.confirmLabel) { submit(prompt) }
        }
    }

    @ViewBuilder
    private func folderMenu(for folder: FolderNode) -> some View {
        Button("Neuer Unterordner", systemImage: "folder.badge.plus") {
            ask(.create(parent: folder.url))
        }
        Button("Umbenennen", systemImage: "pencil") {
            ask(.rename(folder))
        }
        Divider()
        Button("Löschen", systemImage: "trash", role: .destructive) {
            Task { await store.deleteFolder(folder.url) }
        }
    }

    private func ask(_ prompt: FolderPrompt) {
        folderName = prompt.initialName
        self.prompt = prompt
    }

    private func submit(_ prompt: FolderPrompt) {
        let name = folderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            switch prompt {
            case .create(let parent): await store.newFolder(in: parent, name: name)
            case .rename(let folder): await store.renameFolder(folder.url, to: name)
            }
        }
    }

    private var promptIsPresented: Binding<Bool> {
        Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })
    }
}

private enum FolderPrompt {
    case create(parent: URL?)
    case rename(FolderNode)

    var title: String {
        switch self {
        case .create(nil): "Neuer Ordner"
        case .create: "Neuer Unterordner"
        case .rename: "Ordner umbenennen"
        }
    }

    var confirmLabel: String {
        switch self {
        case .create: "Anlegen"
        case .rename: "Umbenennen"
        }
    }

    var initialName: String {
        switch self {
        case .create: ""
        case .rename(let folder): folder.name
        }
    }
}
