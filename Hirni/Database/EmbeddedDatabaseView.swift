import HirniKit
import SwiftUI

/// Eine Datenbank-Ansicht mitten in einer Notiz: Kopf mit Name und
/// «Öffnen», darunter Tabelle, Kalender oder Diagramm. Einträge lassen sich
/// antippen und im Formular bearbeiten.
struct EmbeddedDatabaseView: View {
    let embed: DatabaseEmbed
    let registry: EmbeddedDatabases

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
        // Passt der Inhalt nicht ganz, wird unten abgeschnitten statt nach
        // oben über den Text hinaus gezeichnet.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tablecells")
                .foregroundStyle(.tint)
            Text(title)
                .font(.subheadline.bold())
                .lineLimit(1)
            if case .loaded(let document) = registry.state(for: embed) {
                Text(document.currentView.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Group {
                    Button("Neuer Eintrag", systemImage: "plus") {
                        registry.editingRow = .init(document: document, rowID: document.addRow())
                    }
                    .help("Neuer Eintrag")
                    Button("Felder", systemImage: "slider.horizontal.3") {
                        registry.editingFields = .init(document: document)
                    }
                    .help("Felder bearbeiten")
                    Button("Öffnen", systemImage: "arrow.up.right.square") {
                        registry.store.selectedNote = document.url
                    }
                    .help("Datenbank öffnen")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: EmbeddedDatabases.headerHeight)
    }

    private var title: String {
        if case .loaded(let document) = registry.state(for: embed) { return document.title }
        return embed.database.isEmpty ? "Datenbank" : (embed.database as NSString).lastPathComponent
    }

    @ViewBuilder
    private var content: some View {
        switch registry.state(for: embed) {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .missing:
            Label(
                embed.database.isEmpty
                    ? "Im Block fehlt «datenbank: Name»."
                    : "Datenbank «\(embed.database)» nicht gefunden.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(12)
        case .loaded(let document):
            switch document.currentView.kind {
            case .table:
                EmbeddedRows(document: document, registry: registry)
            case .list:
                EmbeddedList(document: document, registry: registry)
            case .calendar:
                DatabaseCalendar(document: document) { id in
                    // Erst öffnen, wenn das Tagesblatt zu ist.
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        registry.editingRow = .init(document: document, rowID: id)
                    }
                }
            case .chart:
                DatabaseChart(document: document)
            }
        }
    }
}

/// Die Tabelle mit allen sichtbaren Spalten, die ersten Einträge.
private struct EmbeddedRows: View {
    let document: DatabaseDocument
    let registry: EmbeddedDatabases

    var body: some View {
        let result = document.result
        VStack(alignment: .leading, spacing: 0) {
            if result.rows.isEmpty {
                Text(document.database.rows.isEmpty ? "Noch keine Einträge – mit + oben anlegen" : "Keine passenden Einträge")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                DatabaseGrid(document: document, limit: EmbeddedDatabases.maxRows) { id in
                    registry.editingRow = .init(document: document, rowID: id)
                }
            }
            if result.rows.count > EmbeddedDatabases.maxRows {
                Button("\(result.rows.count - EmbeddedDatabases.maxRows) weitere – Datenbank öffnen") {
                    registry.store.selectedNote = document.url
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .frame(height: 32)
            }
        }
        .onChange(of: result.rows.count) { registry.onLayoutChange() }
        .onChange(of: document.currentView.aggregates?.isEmpty) { registry.onLayoutChange() }
    }
}

/// Ansicht «Liste» in kurz: die ersten Einträge mit Titel und Werten.
private struct EmbeddedList: View {
    let document: DatabaseDocument
    let registry: EmbeddedDatabases

    var body: some View {
        let result = document.result
        let fields = document.visibleFields
        VStack(alignment: .leading, spacing: 0) {
            if result.rows.isEmpty {
                Text(document.database.rows.isEmpty ? "Noch keine Einträge – mit + oben anlegen" : "Keine passenden Einträge")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            ForEach(result.rows.prefix(EmbeddedDatabases.maxRows)) { row in
                Button { registry.editingRow = .init(document: document, rowID: row.id) } label: {
                    RowSummary(fields: fields, row: row, hasPage: document.rowPages[row.id] != nil)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: EmbeddedDatabases.listRowHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 12)
            }
            if result.rows.count > EmbeddedDatabases.maxRows {
                Button("\(result.rows.count - EmbeddedDatabases.maxRows) weitere – Datenbank öffnen") {
                    registry.store.selectedNote = document.url
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .frame(height: 32)
            }
            let aggregates = document.currentView.aggregates ?? [:]
            if !aggregates.isEmpty {
                let parts = document.database.fields.compactMap { field -> String? in
                    aggregates[field.name].map { "\($0.label) \(field.name): \(DatabaseQuery.display($0, field: field, rows: result.rows))" }
                }
                Text(parts.joined(separator: " · "))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
            }
        }
        .onChange(of: result.rows.count) { registry.onLayoutChange() }
    }
}

/// Auswahl «Datenbank einfügen»: alle Datenbanken mit ihren Ansichten.
struct DatabasePicker: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let note: URL
    let insert: (String) -> Void

    @State private var databases: [(url: URL, views: [SavedView])] = []
    @State private var isLoaded = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $newName, prompt: Text("z. B. Ausgaben Sommerferien"))
                        .onSubmit(createDatabase)
                    Button("Neue Datenbank anlegen", systemImage: "plus.rectangle.on.rectangle", action: createDatabase)
                } header: {
                    Text("Neue Datenbank")
                } footer: {
                    Text("Sie liegt im Ordner dieser Notiz und hat zuerst nur das Feld «Name». Weitere Felder im Kasten unter «Felder».")
                }
                ForEach(databases, id: \.url) { database in
                    Section(Vault.title(of: database.url)) {
                        // Ohne gespeicherte Ansicht: die Tabelle «Alle».
                        ForEach(database.views.isEmpty ? [SavedView(name: "")] : database.views, id: \.name) { view in
                            Button {
                                let reference = store.vault.databaseReference(for: database.url, from: note)
                                insert(DatabaseEmbed.markdown(database: reference, view: view.name.isEmpty ? nil : view.name))
                                dismiss()
                            } label: {
                                Label(view.name.isEmpty ? "Alle" : view.name, systemImage: view.kind.systemImage)
                            }
                        }
                    }
                }
            }
            .overlay {
                if isLoaded && databases.isEmpty {
                    ContentUnavailableView("Keine Datenbanken", systemImage: "tablecells", description: Text("Zuerst in der Notizliste eine Datenbank anlegen."))
                }
            }
            .navigationTitle("Datenbank einfügen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
        .task { await loadDatabases() }
    }

    private func createDatabase() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        Task {
            guard let url = await store.createDatabase(in: note.deletingLastPathComponent(), title: name.isEmpty ? "Neue Datenbank" : name)
            else { return }
            insert(DatabaseEmbed.markdown(database: store.vault.databaseReference(for: url, from: note), view: nil))
            dismiss()
        }
    }

    private func loadDatabases() async {
        let vault = store.vault
        databases = await Task.detached {
            vault.databases().map { url in
                (url, (try? vault.readDatabase(at: url))?.views ?? [])
            }
        }.value
        isLoaded = true
    }
}
