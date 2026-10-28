import SwiftUI

@main
struct HirniApp: App {
    @State private var vault = VaultLocator()

    init() {
        ReminderScheduler.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vault)
                .task { await vault.locate() }
        }
    }
}
