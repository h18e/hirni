import SwiftUI

/// Platzhalter für Etappe 0: zeigt nur, ob der iCloud-Ordner gefunden wurde.
/// Ab Etappe 1 kommt hier die eigentliche Navigation (Ordner | Liste | Inhalt).
struct RootView: View {
    @Environment(VaultLocator.self) private var vault

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("hirni")
                .font(.largeTitle.bold())
            status
        }
        .padding(32)
        .frame(minWidth: 320, minHeight: 320)
    }

    @ViewBuilder
    private var status: some View {
        switch vault.state {
        case .searching:
            ProgressView("Suche iCloud-Ordner …")
        case .ready(let url):
            Label("iCloud verbunden", systemImage: "checkmark.icloud")
                .foregroundStyle(.green)
            Text(url.path(percentEncoded: false))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
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
