import HirniKit
import SwiftUI

/// Hauptansicht: Ordner | Notizliste | Editor.
/// Auf dem iPhone klappt `NavigationSplitView` das automatisch zu einem Stapel
/// zusammen, durch den man sich hindurchtippt.
struct LibraryView: View {
    @State private var store: VaultStore
    @Environment(\.scenePhase) private var scenePhase

    init(vault: Vault) {
        _store = State(initialValue: VaultStore(vault: vault))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            if store.sidebarSelection == .trash {
                TrashListView()
            } else if store.sidebarSelection == .tasks {
                TasksView()
            } else if store.sidebarSelection == .help {
                HelpListView()
            } else {
                NoteListView()
            }
        } detail: {
            if store.sidebarSelection == .help {
                if let topic = HelpTopic.all.first(where: { $0.id == store.helpTopic }) {
                    HelpTopicView(topic: topic)
                } else {
                    ContentUnavailableView("Thema wählen", systemImage: "questionmark.circle", description: Text("Links ein Thema antippen oder oben suchen."))
                }
            } else if let url = store.selectedNote, Vault.isDatabase(url) {
                DatabaseView(url: url)
                    .id(url)
            } else if let url = store.selectedNote {
                NoteEditorView(url: url)
            } else {
                ContentUnavailableView("Keine Notiz ausgewählt", systemImage: "note.text")
            }
        }
        .sheet(item: Binding(get: { store.askingTemplate }, set: { store.askingTemplate = $0 })) { asking in
            TemplateQuestionsSheet(asking: asking)
                .environment(store)
        }
        .environment(store)
        .task {
            AppRouter.shared.handler = { [store] in store.open($0) }
            await store.start()
        }
        .onOpenURL { url in
            if let destination = AppDestination(url: url) { store.open(destination) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.importShared(); await store.reload() } }
            // In den Hintergrund: sofort speichern, iOS beendet Apps dort ohne Vorwarnung.
            if phase == .background, let editor = store.openEditor { Task { await editor.flush() } }
        }
        .alert("Das hat nicht geklappt", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }
}
