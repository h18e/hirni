import HirniKit
import SwiftUI

/// Eine geöffnete Datenbank. Am Mac als Tabelle mit direkter Bearbeitung,
/// auf dem iPhone als Liste, ein Tipp öffnet das Formular.
struct DatabaseView: View {
    @Environment(VaultStore.self) private var store
    let url: URL

    @State private var document: DatabaseDocument?
    @State private var title = ""
    @State private var editingRow: EditingRow?
    @State private var showsFields = false
    @State private var selection = Set<String>()

    var body: some View {
        Group {
            if let document, document.isLoaded {
                content(document)
            } else if let error = document?.loadError {
                ContentUnavailableView("Datenbank lässt sich nicht öffnen", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView("Wird geladen …")
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: url) {
            let document = DatabaseDocument(store: store, url: url)
            self.document = document
            await document.load()
            title = document.title
        }
        .onChange(of: store.revision) {
            Task { await document?.reloadIfChangedElsewhere() }
        }
        .onDisappear {
            if let document { Task { await document.close() } }
        }
    }

    private func content(_ document: DatabaseDocument) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let notice = document.mergeNotice {
                HStack {
                    Label(notice, systemImage: "arrow.triangle.merge")
                        .font(.subheadline)
                    Spacer()
                    Button("OK") { document.mergeNotice = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(12)
                .background(.orange.opacity(0.15))
            }

            TextField("Titel", text: $title)
                .font(.title.bold())
                .textFieldStyle(.plain)
                .onSubmit { Task { await document.rename(to: title) } }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            #if os(macOS)
            DatabaseTable(document: document, selection: $selection)
            #else
            DatabaseRowList(document: document) { editingRow = EditingRow(id: $0) }
            #endif
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Felder", systemImage: "slider.horizontal.3") { showsFields = true }
                Button("Neuer Eintrag", systemImage: "plus") {
                    let id = document.addRow()
                    #if os(iOS)
                    editingRow = EditingRow(id: id)
                    #else
                    selection = [id]
                    #endif
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
        .sheet(item: $editingRow) { row in
            RowFormView(document: document, rowID: row.id)
        }
        .sheet(isPresented: $showsFields) {
            FieldsEditorView(document: document)
        }
    }
}

private struct EditingRow: Identifiable {
    let id: String
}

#if os(macOS)
/// Mac: alle Felder als Spalten, Werte direkt in der Zelle bearbeiten.
private struct DatabaseTable: View {
    let document: DatabaseDocument
    @Binding var selection: Set<String>

    var body: some View {
        Table(document.database.rows, selection: $selection) {
            TableColumnForEach(document.database.fields) { field in
                TableColumn(field.name) { row in
                    CellEditor(field: field, raw: binding(row: row.id, field: field.name), compact: true)
                }
                .width(min: 60, ideal: field.type == .text ? 200 : 110)
            }
        }
        .onDeleteCommand {
            document.deleteRows(selection)
            selection = []
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Löschen", systemImage: "trash", role: .destructive) {
                document.deleteRows(ids)
            }
        }
        .overlay {
            if document.database.rows.isEmpty {
                ContentUnavailableView("Noch keine Einträge", systemImage: "tablecells", description: Text("Mit + oben einen Eintrag hinzufügen (⇧⌘N)."))
            }
        }
    }

    private func binding(row id: String, field: String) -> Binding<String> {
        Binding(
            get: { document.value(row: id, field: field) },
            set: { document.setValue($0, row: id, field: field) }
        )
    }
}
#endif

#if os(iOS)
/// iPhone: eine Zeile pro Eintrag mit dem ersten Feld als Titel und den
/// nächsten zwei Werten darunter.
private struct DatabaseRowList: View {
    let document: DatabaseDocument
    let open: (String) -> Void

    var body: some View {
        List {
            ForEach(document.database.rows) { row in
                Button { open(row.id) } label: {
                    RowSummary(fields: document.database.fields, row: row)
                }
                .tint(.primary)
                .swipeActions {
                    Button("Löschen", systemImage: "trash", role: .destructive) {
                        document.deleteRows([row.id])
                    }
                }
            }
            .onMove { document.moveRows(from: $0, to: $1) }
        }
        .overlay {
            if document.database.rows.isEmpty {
                ContentUnavailableView("Noch keine Einträge", systemImage: "tablecells", description: Text("Mit + oben einen Eintrag hinzufügen."))
            }
        }
    }
}

private struct RowSummary: View {
    let fields: [Field]
    let row: Row

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            let first = fields.first.map { CellValue.display(row[$0.name], for: $0) } ?? ""
            Text(first.isEmpty ? "Ohne Namen" : first)
                .font(.headline)
                .foregroundStyle(first.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            let details = fields.dropFirst().prefix(3)
                .map { CellValue.display(row[$0.name], for: $0) }
                .filter { !$0.isEmpty }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
#endif

/// Formular für einen Eintrag: alle Felder untereinander.
struct RowFormView: View {
    let document: DatabaseDocument
    let rowID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ForEach(document.database.fields) { field in
                    LabeledContent {
                        CellEditor(field: field, raw: Binding(
                            get: { document.value(row: rowID, field: field.name) },
                            set: { document.setValue($0, row: rowID, field: field.name) }
                        ))
                    } label: {
                        Label(field.name, systemImage: field.type.systemImage)
                    }
                }
                Section {
                    Button("Eintrag löschen", systemImage: "trash", role: .destructive) {
                        document.deleteRows([rowID])
                        dismiss()
                    }
                }
            }
            .navigationTitle("Eintrag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}
