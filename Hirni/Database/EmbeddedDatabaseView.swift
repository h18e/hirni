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
                Button("Öffnen", systemImage: "arrow.up.right.square") {
                    registry.store.selectedNote = document.url
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Datenbank öffnen")
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

/// Tabelle in kurz: pro Eintrag das erste Feld und die nächsten Werte.
private struct EmbeddedRows: View {
    let document: DatabaseDocument
    let registry: EmbeddedDatabases

    var body: some View {
        let result = document.result
        let fields = document.visibleFields
        VStack(alignment: .leading, spacing: 0) {
            if result.rows.isEmpty {
                Text(document.database.rows.isEmpty ? "Noch keine Einträge" : "Keine passenden Einträge")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            ForEach(result.rows.prefix(EmbeddedDatabases.maxRows)) { row in
                Button { registry.editingRow = .init(document: document, rowID: row.id) } label: {
                    line(row, fields: fields)
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

    private func line(_ row: Row, fields: [Field]) -> some View {
        let first = fields.first.map { CellValue.display(row[$0.name], for: $0) } ?? ""
        let details = fields.dropFirst().prefix(3)
            .map { CellValue.display(row[$0.name], for: $0) }
            .filter { !$0.isEmpty }
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(first.isEmpty ? "Ohne Namen" : first)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(first.isEmpty ? .secondary : .primary)
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer()
            if document.rowPages[row.id] != nil {
                Image(systemName: "doc.text").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: EmbeddedDatabases.rowHeight)
        .contentShape(Rectangle())
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

    var body: some View {
        NavigationStack {
            List {
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
        .task {
            let vault = store.vault
            databases = await Task.detached {
                vault.databases().map { url in
                    (url, (try? vault.readDatabase(at: url))?.views ?? [])
                }
            }.value
            isLoaded = true
        }
    }
}
