import HirniKit
import SwiftUI

struct SidebarView: View {
    @Environment(VaultStore.self) private var store

    @State private var prompt: FolderPrompt?
    @State private var folderName = ""
    @State private var moving: MovingItem?

    var body: some View {
        @Bindable var store = store

        List(selection: $store.sidebarSelection) {
            Label(VaultLayout.inboxFolderName, systemImage: "tray")
                .tag(SidebarItem.inbox)
                .dropDestination(for: VaultItemTransfer.self) { items, _ in
                    drop(items, into: store.vault.inboxURL)
                }

            Label("Pendenzen", systemImage: "checklist")
                .badge(store.tasks.filter { !$0.isDone }.count)
                .tag(SidebarItem.tasks)

            Section("Ordner") {
                #if os(macOS)
                OutlineGroup(store.folders, children: \.childrenOrNil) { folder in
                    folderRow(folder)
                }
                #else
                // Auf dem iPhone klappt ein Tipp auf einen Ordner mit Unterordnern
                // nur auf, statt ihn zu öffnen. Darum hier nur die obersten; die
                // Unterordner stehen zuoberst in der Liste des Ordners.
                ForEach(store.folders) { folder in
                    folderRow(folder)
                }
                #endif
            }

            if !store.tagCounts.isEmpty {
                Section("Tags") {
                    ForEach(store.tagCounts) { tag in
                        Label(tag.name, systemImage: "number")
                            .badge(tag.count)
                            .tag(SidebarItem.tag(tag.name))
                    }
                }
            }

            Section {
                Label("Zuletzt gelöscht", systemImage: "trash")
                    .tag(SidebarItem.trash)
            } footer: {
                let count = store.iCloudStatus.downloading.count
                if count > 0 {
                    Label("iCloud lädt \(count) \(count == 1 ? "Datei" : "Dateien") …", systemImage: "icloud.and.arrow.down")
                }
            }
        }
        .navigationTitle("Hirni")
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
        .sheet(item: $moving) { item in
            FolderPickerView(item: item.url)
        }
        .alert(prompt?.title ?? "", isPresented: promptIsPresented, presenting: prompt) { prompt in
            TextField("Name", text: $folderName)
            Button("Abbrechen", role: .cancel) {}
            Button(prompt.confirmLabel) { submit(prompt) }
        }
    }

    private func folderRow(_ folder: FolderNode) -> some View {
        Label(folder.name, systemImage: "folder")
            .tag(SidebarItem.folder(folder.url))
            .draggable(VaultItemTransfer(url: folder.url)) {
                Label(folder.name, systemImage: "folder")
            }
            .dropDestination(for: VaultItemTransfer.self) { items, _ in
                drop(items, into: folder.url)
            }
            .contextMenu { folderMenu(for: folder) }
    }

    @ViewBuilder
    private func folderMenu(for folder: FolderNode) -> some View {
        Button("Neuer Unterordner", systemImage: "folder.badge.plus") {
            ask(.create(parent: folder.url))
        }
        Button("Umbenennen", systemImage: "pencil") {
            ask(.rename(folder))
        }
        Button("Verschieben nach …", systemImage: "folder") {
            moving = MovingItem(url: folder.url)
        }
        Divider()
        Button("Löschen", systemImage: "trash", role: .destructive) {
            Task { await store.deleteFolder(folder.url) }
        }
    }

    /// Abgelegte Notizen oder Ordner in `folder` verschieben. Nur Elemente aus
    /// dem hirni-Ordner werden angenommen.
    private func drop(_ items: [VaultItemTransfer], into folder: URL) {
        let urls = items.map(\.url).filter { store.vault.contains($0) && !folder.isInside($0) }
        Task {
            for url in urls { await store.move(url, to: folder) }
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
