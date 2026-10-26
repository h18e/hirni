import HirniKit
import SwiftUI

/// Eine geöffnete Datenbank. Am Mac als Tabelle mit direkter Bearbeitung,
/// auf dem iPhone als Liste, ein Tipp öffnet das Formular. Oben die
/// Ansichten und ihre Einstellungen (Filter, Sortierung …).
struct DatabaseView: View {
    @Environment(VaultStore.self) private var store
    let url: URL

    @State private var document: DatabaseDocument?
    @State private var title = ""
    @State private var editingRow: EditingRow?
    @State private var showsFields = false
    @State private var selection = Set<String>()
    /// Geöffnete Zeilen-Seite.
    @State private var page: URL?

    var body: some View {
        Group {
            if let document, document.isLoaded {
                // Eigener Stapel für die Zeilen-Seite (mit Zurück-Knopf): Die
                // Detailspalte hat keine Spalte mehr, in die sie sich öffnen könnte.
                NavigationStack { content(document) }
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
                .padding(.bottom, 4)

            ViewBar(document: document)
            ViewOptions(document: document)
            Divider()

            switch document.currentView.kind {
            case .calendar:
                DatabaseCalendar(document: document) { id in
                    // Erst öffnen, wenn das Tagesblatt zu ist: zwei Blätter
                    // gleichzeitig zeigt das System nicht zuverlässig an.
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        editingRow = EditingRow(id: id)
                    }
                }
            case .chart:
                ScrollView { DatabaseChart(document: document) }
            case .table:
                #if os(macOS)
                DatabaseTable(document: document, selection: $selection, openPage: { showPage($0) })
                #else
                DatabaseRowList(document: document, open: { editingRow = EditingRow(id: $0) }, openPage: { showPage($0) })
                #endif
            }
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
            RowFormView(document: document, rowID: row.id) { id in
                editingRow = nil
                showPage(id, afterSheet: true)
            }
        }
        .navigationDestination(item: $page) { url in
            NoteEditorView(url: url)
        }
        .onChange(of: page) { _, page in
            // Die Seite hatte sich beim Store angemeldet, jetzt wieder die Datenbank.
            if page == nil { document.register() }
        }
        .sheet(isPresented: $showsFields) {
            FieldsEditorView(document: document)
        }
    }
}

extension DatabaseView {
    /// Öffnet die Seite einer Zeile und legt sie bei Bedarf an. Aus einem
    /// Blatt heraus erst, wenn es zu ist.
    private func showPage(_ rowID: String, afterSheet: Bool = false) {
        Task {
            if afterSheet { try? await Task.sleep(for: .milliseconds(400)) }
            page = await document?.page(for: rowID)
        }
    }
}

private struct EditingRow: Identifiable {
    let id: String
}

#if os(macOS)
/// Mac: alle sichtbaren Felder als Spalten, Werte direkt in der Zelle bearbeiten.
///
/// Bewusst ein eigenes Raster statt SwiftUIs `Table`: `Table` mit
/// wechselnden Spalten (`TableColumnForEach`) stürzte beim Bearbeiten ab
/// (Absturz in AttributeGraph beim Aufbau der Spaltenliste).
private struct DatabaseTable: View {
    let document: DatabaseDocument
    @Binding var selection: Set<String>
    let openPage: (String) -> Void

    private let handleWidth: CGFloat = 48

    var body: some View {
        let result = document.result
        let fields = document.visibleFields
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders, .sectionFooters]) {
                Section {
                    ForEach(result.groups) { group in
                        if let title = group.title {
                            groupHeader(title, count: group.rows.count)
                        }
                        ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                            rowView(row, number: index + 1, fields: fields)
                        }
                    }
                } header: {
                    header(fields)
                } footer: {
                    footer(fields, rows: result.rows)
                }
            }
            .padding(.bottom, 20)
        }
        // Ist die Tabelle schmaler als das Fenster, steht sie links oben statt in der Mitte.
        .defaultScrollAnchor(.topLeading, for: .alignment)
        .overlay {
            if document.database.rows.isEmpty {
                ContentUnavailableView("Noch keine Einträge", systemImage: "tablecells", description: Text("Mit + oben einen Eintrag hinzufügen (⇧⌘N)."))
            } else if result.rows.isEmpty {
                ContentUnavailableView("Keine passenden Einträge", systemImage: "line.3.horizontal.decrease", description: Text("Die Filter dieser Ansicht treffen auf keinen Eintrag zu."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Auswahl löschen", systemImage: "trash") {
                    document.deleteRows(selection)
                    selection = []
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(selection.isEmpty)
                .help("Gewählte Einträge löschen (⌘⌫)")
            }
        }
    }

    /// Überschriften lassen sich ziehen: Loslassen auf einer anderen
    /// Überschrift setzt die Spalte davor, ganz rechts ans Ende.
    private func header(_ fields: [Field]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: handleWidth)
            ForEach(fields) { field in
                ColumnHeader(field: field, width: width(of: field)) { dragged in
                    document.moveField(dragged, before: field.name)
                }
                Divider()
            }
            // Platz rechts der letzten Spalte: dort abgelegt kommt sie ans Ende.
            Color.clear
                .frame(width: 80)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { names, _ in
                    guard let name = names.first, document.database.field(named: name) != nil else { return false }
                    document.moveField(name, before: nil)
                    return true
                }
        }
        .frame(height: 28)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Berechnungen unter den Spalten, über alle sichtbaren Einträge.
    @ViewBuilder
    private func footer(_ fields: [Field], rows: [Row]) -> some View {
        let aggregates = document.currentView.aggregates ?? [:]
        if !aggregates.isEmpty {
            HStack(spacing: 0) {
                Color.clear.frame(width: handleWidth)
                ForEach(fields) { field in
                    Group {
                        if let aggregate = aggregates[field.name] {
                            HStack(spacing: 4) {
                                Text(aggregate.label).foregroundStyle(.secondary)
                                Text(DatabaseQuery.display(aggregate, field: field, rows: rows)).bold()
                            }
                        } else {
                            Color.clear
                        }
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(width: width(of: field), alignment: field.type == .number ? .trailing : .leading)
                    Divider()
                }
            }
            .frame(height: 28)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func groupHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline.bold())
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.leading, handleWidth + 8)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06))
    }

    private func rowView(_ row: Row, number: Int, fields: [Field]) -> some View {
        let isSelected = selection.contains(row.id)
        return HStack(spacing: 0) {
            // Zeilennummer: Klick wählt die Zeile (⌘-Klick: mehrere).
            // Daneben das Symbol der Zeilen-Seite, falls es eine gibt.
            HStack(spacing: 2) {
                Text("\(number)")
                    .font(.caption.monospacedDigit())
                if document.rowPages[row.id] != nil {
                    Button("Seite öffnen", systemImage: "doc.text") { openPage(row.id) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .help("Seite öffnen")
                }
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .frame(width: handleWidth, height: 30)
            .background(isSelected ? Color.accentColor : .clear)
            .contentShape(Rectangle())
            .onTapGesture { toggle(row.id) }
            ForEach(fields) { field in
                CellEditor(field: field, raw: binding(row: row.id, field: field.name), compact: true)
                    .padding(.horizontal, 8)
                    .frame(width: width(of: field), height: 30, alignment: .leading)
                Divider()
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.12) : (number.isMultiple(of: 2) ? Color.primary.opacity(0.03) : .clear))
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
        .contextMenu {
            Button(document.rowPages[row.id] == nil ? "Seite anlegen" : "Seite öffnen", systemImage: "doc.text") {
                openPage(row.id)
            }
            Divider()
            Button("Löschen", systemImage: "trash", role: .destructive) {
                document.deleteRows(selection.contains(row.id) ? selection : [row.id])
                selection = []
            }
        }
    }

    private func toggle(_ id: String) {
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = selection == [id] ? [] : [id]
        }
    }

    private func width(of field: Field) -> CGFloat {
        switch field.type {
        case .text, .url: 220
        case .multiSelect: 170
        case .date: (field.includesTime ?? false) ? 190 : 150
        case .checkbox: 80
        case .number, .select: 130
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

#if os(macOS)
/// Eine Spaltenüberschrift, die sich ziehen lässt und gezogene Spalten annimmt.
private struct ColumnHeader: View {
    let field: Field
    let width: CGFloat
    let drop: (String) -> Void
    @State private var isTargeted = false

    var body: some View {
        Label(field.name, systemImage: field.type.systemImage)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(width: width, height: 28, alignment: .leading)
            .contentShape(Rectangle())
            // Einfügemarke links: Hier landet die gezogene Spalte.
            .overlay(alignment: .leading) {
                if isTargeted { Rectangle().fill(Color.accentColor).frame(width: 3) }
            }
            .draggable(field.name) {
                Label(field.name, systemImage: field.type.systemImage)
                    .font(.caption.bold())
                    .padding(6)
                    .background(.bar, in: RoundedRectangle(cornerRadius: 6))
            }
            .dropDestination(for: String.self) { names, _ in
                guard let name = names.first, name != field.name else { return false }
                drop(name)
                return true
            } isTargeted: { isTargeted = $0 }
            .help("Ziehen, um die Spalte zu verschieben")
    }
}
#endif

#if os(iOS)
/// iPhone: eine Zeile pro Eintrag mit dem ersten Feld als Titel und den
/// nächsten Werten darunter, gruppiert wie die Ansicht. Unten die Berechnungen.
private struct DatabaseRowList: View {
    let document: DatabaseDocument
    let open: (String) -> Void
    let openPage: (String) -> Void

    var body: some View {
        let result = document.result
        let fields = document.visibleFields
        List {
            ForEach(result.groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        Button { open(row.id) } label: {
                            RowSummary(fields: fields, row: row, hasPage: document.rowPages[row.id] != nil)
                        }
                        .tint(.primary)
                        .swipeActions {
                            Button("Löschen", systemImage: "trash", role: .destructive) {
                                document.deleteRows([row.id])
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Seite", systemImage: "doc.text") { openPage(row.id) }
                                .tint(.blue)
                        }
                    }
                } header: {
                    if let title = group.title {
                        Text("\(title) · \(group.rows.count)")
                    }
                }
            }

            let aggregates = document.currentView.aggregates ?? [:]
            if !aggregates.isEmpty {
                Section("Berechnungen") {
                    ForEach(document.database.fields.filter { aggregates[$0.name] != nil }) { field in
                        if let aggregate = aggregates[field.name] {
                            LabeledContent("\(aggregate.label) \(field.name)") {
                                Text(DatabaseQuery.display(aggregate, field: field, rows: result.rows)).bold()
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if document.database.rows.isEmpty {
                ContentUnavailableView("Noch keine Einträge", systemImage: "tablecells", description: Text("Mit + oben einen Eintrag hinzufügen."))
            } else if result.rows.isEmpty {
                ContentUnavailableView("Keine passenden Einträge", systemImage: "line.3.horizontal.decrease", description: Text("Die Filter dieser Ansicht treffen auf keinen Eintrag zu."))
            }
        }
    }
}

private struct RowSummary: View {
    let fields: [Field]
    let row: Row
    let hasPage: Bool

    var body: some View {
        HStack {
            details
            if hasPage {
                Spacer()
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Hat eine Seite")
            }
        }
    }

    private var details: some View {
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
    /// Zeilen-Seite öffnen. Das Formular schliesst sich dabei.
    let openPage: (String) -> Void
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
                    Button(document.rowPages[rowID] == nil ? "Seite anlegen" : "Seite öffnen", systemImage: "doc.text") {
                        openPage(rowID)
                    }
                } footer: {
                    if document.rowPages[rowID] == nil {
                        Text("Eine eigene Notiz zu diesem Eintrag, für Details, Bilder und Checklisten.")
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
