import AppIntents
import SwiftUI

@main
struct HirniApp: App {
    @State private var vault = VaultLocator()
    #if os(macOS)
    @AppStorage("menueleisteAnzeigen") private var showsMenuBarExtra = true
    #endif

    init() {
        ReminderScheduler.shared.install()
        // Siri die aktuellen Sätze melden (sonst kennt sie sie erst später).
        HirniShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(vault)
                .task { await vault.locate() }
        }
        #if os(macOS)
        .commands { NoteWindowCommands() }
        #endif

        #if os(macOS)
        // Eigenständige Fenster mit einer oder mehreren Notizen. Links aus Widget und
        // Mitteilungen gehen weiter ans Hauptfenster.
        WindowGroup("Notiz", id: NoteWindow.id, for: [URL].self) { $notes in
            RootView(notes: notes)
                .environment(vault)
                .task { await vault.locate() }
        }
        .defaultSize(width: 760, height: 820)
        .commandsRemoved()
        .handlesExternalEvents(matching: [])

        MenuBarExtra("Hirni", systemImage: "brain.head.profile", isInserted: $showsMenuBarExtra) {
            MenuBarQuickNote()
                .environment(vault)
        }
        .menuBarExtraStyle(.window)

        Settings {
            HirniSettings()
        }
        #endif
    }
}
