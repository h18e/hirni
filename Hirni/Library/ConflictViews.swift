import HirniKit
import SwiftUI

/// Hinweis oben im Editor: Die Notiz wurde anderswo geändert, während du
/// hier getippt hast, und die Änderungen betreffen dieselbe Stelle.
struct ExternalChangeBanner: View {
    let keepMine: () -> Void
    let takeTheirs: () -> Void
    let keepBoth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Diese Notiz wurde gleichzeitig anderswo geändert", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.subheadline.bold())
            Text("Deine Eingaben und die andere Änderung betreffen dieselbe Stelle. Bis du entscheidest, wird nichts gespeichert.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Meine behalten", action: keepMine)
                Button("Andere übernehmen", action: takeTheirs)
                Button("Beide behalten", action: keepBoth)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.15))
    }
}

/// Hinweis oben im Editor: iCloud hat mehrere Fassungen dieser Notiz.
struct ConflictBanner: View {
    let show: () -> Void

    var body: some View {
        HStack {
            Label("Von dieser Notiz gibt es mehrere Fassungen", systemImage: "doc.on.doc")
                .font(.subheadline.bold())
            Spacer()
            Button("Ansehen", action: show)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .background(.orange.opacity(0.15))
    }
}

/// Alle Fassungen einer Notiz nebeneinander, mit der Wahl, welche bleibt.
struct ConflictResolverView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let url: URL
    /// Der Text, wie er gerade im Editor steht.
    let currentText: String

    @State private var versions: [ConflictVersion] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VersionPreview(text: Frontmatter.split(currentText).body)
                    Button("Diese behalten") { resolve(.keepCurrent) }
                } header: {
                    Text("Auf diesem Gerät")
                }

                ForEach(versions) { version in
                    Section {
                        VersionPreview(text: Frontmatter.split(version.text).body)
                        Button("Diese übernehmen") { resolve(.takeOther(version)) }
                    } header: {
                        Text(title(of: version))
                    }
                }

                Section {
                    Button("Alle behalten") { resolve(.keepAll) }
                } footer: {
                    Text("Die anderen Fassungen werden zu eigenen Notizen im selben Ordner, mit dem Gerätenamen im Titel.")
                }
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .navigationTitle("Fassungen von «\(Vault.title(of: url))»")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Später") { dismiss() }
                }
            }
            .task {
                versions = await store.conflictVersions(of: url)
                isLoading = false
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    private func title(of version: ConflictVersion) -> String {
        let device = version.deviceName ?? "Anderes Gerät"
        guard let modified = version.modified else { return device }
        return "\(device) · \(modified.formatted(date: .abbreviated, time: .shortened))"
    }

    private func resolve(_ choice: ConflictChoice) {
        Task {
            await store.resolveConflict(at: url, choice: choice)
            dismiss()
        }
    }
}

private struct VersionPreview: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? "(leer)" : text)
            .font(.callout)
            .lineLimit(12)
            .foregroundStyle(text.isEmpty ? .secondary : .primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
