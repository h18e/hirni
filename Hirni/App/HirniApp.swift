import SwiftUI

@main
struct HirniApp: App {
    @State private var vault = VaultLocator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vault)
                .task { await vault.locate() }
        }
    }
}
