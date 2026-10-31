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
            case .list:
                DatabaseRowList(document: document, open: { editingRow = EditingRow(id: $0) }, openPage: { showPage($0, template: $1) })
            case .table:
                #if os(macOS)
                DatabaseTable(document: document, selection: $selection, openPage: { showPage($0, template: $1) })
                #else
                DatabaseGrid(document: document, open: { editingRow = EditingRow(id: $0) }, openPage: { showPage($0, template: $1) })
                    .overlay {
                        if document.database.rows.isEmpty {
                            ContentUnavailableView("Noch keine Einträge", systemImage: "tablecells", description: Text("Mit + oben einen Eintrag hinzufügen."))
                        } else if document.result.rows.isEmpty {
                            ContentUnavailableView("Keine passenden Einträge", systemImage: "line.3.horizontal.decrease", description: Text("Die Filter dieser Ansicht treffen auf keinen Eintrag zu."))
                        }
                    }
                #endif
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Felder", systemImage: "slider.horizontal.3") { showsFields = true }
                calendarMenu(document)
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
            RowFormView(document: document, rowID: row.id) { id, template in
                editingRow = nil
                showPage(id, template: template, afterSheet: true)
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
    /// Termine dieser Datenbank im eigenen Apple Kalender «Hirni» zeigen.
    private func calendarMenu(_ document: DatabaseDocument) -> some View {
        let dateFields = document.database.fields.filter { $0.type == .date }
        let isOn = document.database.calendarField != nil
        return Menu("Apple Kalender", systemImage: isOn ? "calendar.badge.checkmark" : "calendar.badge.plus") {
            if dateFields.isEmpty {
                Text("Für den Kalender braucht die Datenbank ein Datumsfeld.")
            } else {
                Picker("Im Kalender «Hirni» zeigen", selection: Binding(
                    get: { document.database.calendarField },
                    set: { document.setCalendarField($0) }
                )) {
                    Text("Nicht im Kalender").tag(String?.none)
                    ForEach(dateFields) { field in
                        Text(dateFields.count == 1 ? "Im Kalender «Hirni» zeigen" : "Nach «\(field.name)» im Kalender zeigen")
                            .tag(Optional(field.name))
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }

    /// Öffnet die Seite einer Zeile und legt sie bei Bedarf an. Aus einem
    /// Blatt heraus erst, wenn es zu ist.
    private func showPage(_ rowID: String, template: URL? = nil, afterSheet: Bool = false) {
        Task {
            if afterSheet { try? await Task.sleep(for: .milliseconds(400)) }
            page = await document?.page(for: rowID, template: template)
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
    let openPage: PageOpener

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
                ColumnHeader(field: field, width: width(of: field),
                             resize: { document.resizeColumn(field.name, to: $0, done: $1) }) { dragged in
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
                    .frame(width: width(of: field), alignment: field.type.isNumeric ? .trailing : .leading)
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
                    Button("Seite öffnen", systemImage: "doc.text") { openPage(row.id, nil) }
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
            PageButton(document: document, rowID: row.id, open: openPage)
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

    /// Breite einer Spalte: gezogen oder Vorgabe je Feldtyp.
    private func width(of field: Field) -> CGFloat {
        document.columnWidth(field, default: defaultWidth(of: field))
    }

    private func defaultWidth(of field: Field) -> CGFloat {
        switch field.type {
        case .text, .url: 220
        case .multiSelect: 170
        case .date: (field.includesTime ?? false) ? 190 : 150
        case .checkbox: 80
        case .number, .select, .formula: 130
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



/// Formular für einen Eintrag: alle Felder untereinander.
struct RowFormView: View {
    let document: DatabaseDocument
    let rowID: String
    /// Zeilen-Seite öffnen. Das Formular schliesst sich dabei.
    let openPage: PageOpener
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
                    PageButton(document: document, rowID: rowID, open: openPage)
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
