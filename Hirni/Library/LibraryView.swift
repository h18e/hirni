import HirniKit
import SwiftUI

/// Hauptansicht: Ordner | Notizliste | Editor.
/// Auf dem iPhone klappt `NavigationSplitView` das automatisch zu einem Stapel
/// zusammen, durch den man sich hindurchtippt.
struct LibraryView: View {
    @State private var store: VaultStore
    @Environment(\.scenePhase) private var scenePhase
    /// Eigenes Notiz-Fenster: zeigt nur diese Notiz, ohne Seitenleiste und Liste.
    private let windowNote: URL?

    init(vault: Vault, windowNote: URL? = nil) {
        _store = State(initialValue: VaultStore(vault: vault))
        self.windowNote = windowNote
    }

    var body: some View {
        layout
        .sheet(item: Binding(get: { store.askingTemplate }, set: { store.askingTemplate = $0 })) { asking in
            TemplateQuestionsSheet(asking: asking)
                .environment(store)
        }
        .environment(store)
        #if os(macOS)
        .focusedSceneValue(\.openNote, store.selectedNote)
        #endif
        .task {
            if windowNote == nil { AppRouter.shared.handler = { [store] in store.open($0) } }
            await store.start()
            if let windowNote { store.open(file: windowNote) }
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

    @ViewBuilder
    private var layout: some View {
        if windowNote != nil {
            NavigationStack { detail }
        } else {
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
                detail
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if store.sidebarSelection == .help {
            if let topic = HelpTopic.all.first(where: { $0.id == store.helpTopic }) {
                HelpTopicView(topic: topic)
            } else {
                ContentUnavailableView("Thema wählen", systemImage: "questionmark.circle", description: Text("Links ein Thema antippen oder oben suchen."))
            }
        } else if let url = store.selectedNote {
            VStack(spacing: 0) {
                #if os(iOS)
                if store.tabs.urls.count > 1 {
                    NoteTabBar()
                    Divider()
                }
                #endif
                if Vault.isDatabase(url) {
                    DatabaseView(url: url)
                        .id(url)
                } else {
                    NoteEditorView(url: url)
                }
            }
            #if os(macOS)
            .navigationTitle(Vault.title(of: url))
            #endif
        } else {
            ContentUnavailableView("Keine Notiz ausgewählt", systemImage: "note.text")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }
}
