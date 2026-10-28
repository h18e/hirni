import AppIntents
import SwiftUI

@main
struct HirniApp: App {
    @State private var vault = VaultLocator()

    init() {
        ReminderScheduler.shared.install()
        // Siri die aktuellen Sätze melden (sonst kennt sie sie erst später).
        HirniShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vault)
                .task { await vault.locate() }
        }
    }
}
