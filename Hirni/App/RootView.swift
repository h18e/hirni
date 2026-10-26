import HirniKit
import SwiftUI

/// Sucht beim Start den iCloud-Ordner. Sobald er bereit ist, erscheint die
/// eigentliche App, vorher ein Hinweis.
struct RootView: View {
    @Environment(VaultLocator.self) private var vault

    var body: some View {
        if case .ready(let url) = vault.state {
            LibraryView(vault: Vault(root: url))
                .id(url)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Hirni")
                    .font(.largeTitle.bold())
                status
            }
            .padding(32)
            .frame(minWidth: 320, minHeight: 320)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch vault.state {
        case .searching, .ready:
            ProgressView("Suche iCloud-Ordner …")
        case .iCloudUnavailable:
            Label("iCloud nicht verfügbar", systemImage: "xmark.icloud")
                .foregroundStyle(.orange)
            Text("Bitte in den Einstellungen bei iCloud anmelden und iCloud Drive einschalten.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .failed(let message):
            Label("Fehler", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
    }
}
