import HirniKit
import SwiftUI

/// Leiste mit den gespeicherten Ansichten einer Datenbank.
struct ViewBar: View {
    let document: DatabaseDocument
    @State private var renaming: String?
    @State private var newName = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(views) { view in
                    let isSelected = view.name == document.currentView.name
                    Button {
                        document.selectView(view.name)
                    } label: {
                        Label(view.name, systemImage: view.kind.systemImage)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(isSelected ? .accentColor : .secondary)
                    .contextMenu {
                        Button("Umbenennen", systemImage: "pencil") {
                            newName = view.name
                            renaming = view.name
                        }
                        Button("Duplizieren", systemImage: "plus.square.on.square") { document.duplicateView(view.name) }
                        if document.database.views.count > 1 {
                            Divider()
                            Button("Löschen", systemImage: "trash", role: .destructive) { document.deleteView(view.name) }
                        }
                    }
                }
                Button("Neue Ansicht", systemImage: "plus") { document.addView() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .alert("Ansicht umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Abbrechen", role: .cancel) {}
            Button("Umbenennen") {
                if let renaming { document.renameView(renaming, to: newName) }
            }
        }
    }

    /// Gibt es noch keine gespeicherte Ansicht, steht hier die ungespeicherte «Alle».
    private var views: [SavedView] {
        document.database.views.isEmpty ? [document.currentView] : document.database.views
    }
}

/// Filtern, Sortieren, Gruppieren, Felder ausblenden, Berechnen.
struct ViewOptions: View {
    let document: DatabaseDocument
    @State private var editsFilters = false
    @State private var editsSorts = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                let view = document.currentView
                Button { editsFilters = true } label: {
                    Label(count("Filter", view.filters?.count), systemImage: "line.3.horizontal.decrease")
                }
                .tint(view.filters?.isEmpty == false ? .accentColor : .secondary)

                Button { editsSorts = true } label: {
                    Label(count("Sortieren", view.sorts?.count), systemImage: "arrow.up.arrow.down")
                }
                .tint(view.sorts?.isEmpty == false ? .accentColor : .secondary)

                Menu {
                    Picker("Gruppieren nach", selection: Binding(
                        get: { view.groupBy ?? "" },
                        set: { value in document.updateView { $0.groupBy = value.isEmpty ? nil : value } }
                    )) {
                        Text("Nicht gruppieren").tag("")
                        ForEach(document.database.fields.filter(DatabaseQuery.canGroup)) { Text($0.name).tag($0.name) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(view.groupBy.map { "Gruppiert: \($0)" } ?? "Gruppieren", systemImage: "square.grid.3x1.below.line.grid.1x2")
                }
                .tint(view.groupBy != nil ? .accentColor : .secondary)

                Menu {
                    ForEach(document.database.fields) { field in
                        Toggle(field.name, isOn: Binding(
                            get: { !(view.hiddenFields ?? []).contains(field.name) },
                            set: { visible in
                                document.updateView { view in
                                    var hidden = Set(view.hiddenFields ?? [])
                                    if visible { hidden.remove(field.name) } else { hidden.insert(field.name) }
                                    view.hiddenFields = document.database.fields.map(\.name).filter(hidden.contains)
                                }
                            }
                        ))
                    }
                } label: {
                    Label(count("Felder", (view.hiddenFields?.count).map { -$0 }), systemImage: "eye")
                }
                .tint(view.hiddenFields?.isEmpty == false ? .accentColor : .secondary)

                Menu {
                    ForEach(document.database.fields) { field in
                        Picker(field.name, selection: Binding(
                            get: { view.aggregates?[field.name] },
                            set: { value in
                                document.updateView { view in
                                    var aggregates = view.aggregates ?? [:]
                                    aggregates[field.name] = value
                                    view.aggregates = aggregates
                                }
                            }
                        )) {
                            Text("Keine").tag(Aggregate?.none)
                            ForEach(Aggregate.available(for: field.type), id: \.self) { Text($0.label).tag(Aggregate?.some($0)) }
                        }
                    }
                } label: {
                    Label(count("Berechnen", view.aggregates?.count), systemImage: "sum")
                }
                .tint(view.aggregates?.isEmpty == false ? .accentColor : .secondary)
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderless)
            .font(.subheadline)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
        .menuIndicator(.hidden)
        .sheet(isPresented: $editsFilters) { FilterEditor(document: document) }
        .sheet(isPresented: $editsSorts) { SortEditor(document: document) }
    }

    /// «Filter (2)». Negative Zahl = ausgeblendete Felder.
    private func count(_ title: String, _ number: Int?) -> String {
        guard let number, number != 0 else { return title }
        return number < 0 ? "\(title) (\(-number) ausgeblendet)" : "\(title) (\(number))"
    }
}

// MARK: - Filter

private struct FilterEditor: View {
    let document: DatabaseDocument
    @Environment(\.dismiss) private var dismiss
    @State private var rules: [EditableRule] = []

    struct EditableRule: Identifiable {
        let id = UUID()
        var rule: FilterRule
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach($rules) { $item in
                    Section {
                        Picker("Feld", selection: Binding(
                            get: { item.rule.field },
                            set: { name in
                                item.rule.field = name
                                if let field = document.database.field(named: name),
                                   !FilterCondition.available(for: field.type).contains(item.rule.condition) {
                                    item.rule.condition = FilterCondition.available(for: field.type)[0]
                                    item.rule.value = nil
                                }
                            }
                        )) {
                            ForEach(document.database.fields) { Text($0.name).tag($0.name) }
                        }
                        if let field = document.database.field(named: item.rule.field) {
                            Picker("Bedingung", selection: $item.rule.condition) {
                                ForEach(FilterCondition.available(for: field.type), id: \.self) { Text($0.label).tag($0) }
                            }
                            if item.rule.condition.needsValue {
                                LabeledContent("Wert") {
                                    FilterValueEditor(field: field, value: Binding(
                                        get: { item.rule.value ?? "" },
                                        set: { item.rule.value = $0.isEmpty ? nil : $0 }
                                    ))
                                }
                            }
                        }
                        Button("Filter entfernen", systemImage: "trash", role: .destructive) {
                            rules.removeAll { $0.id == item.id }
                        }
                    }
                }
                Section {
                    Button("Filter hinzufügen", systemImage: "plus") {
                        guard let field = document.database.fields.first else { return }
                        rules.append(EditableRule(rule: FilterRule(field: field.name, condition: FilterCondition.available(for: field.type)[0])))
                    }
                } footer: {
                    Text("Ein Eintrag wird gezeigt, wenn er alle Filter erfüllt.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Filter")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        document.updateView { $0.filters = rules.map(\.rule) }
                        dismiss()
                    }
                }
            }
            .onAppear { rules = (document.currentView.filters ?? []).map { EditableRule(rule: $0) } }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }
}

/// Vergleichswert für einen Filter, passend zum Feldtyp.
private struct FilterValueEditor: View {
    let field: Field
    @Binding var value: String

    var body: some View {
        switch field.type {
        case .select, .multiSelect:
            Picker("Wert", selection: $value) {
                Text("–").tag("")
                ForEach(field.options ?? [], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        case .date:
            DatePicker("Wert", selection: Binding(
                get: { CellValue.date(value)?.start ?? .now },
                set: { value = CellValue.raw(date: .init(start: $0)) }
            ), displayedComponents: .date)
            .labelsHidden()
            .onAppear { if value.isEmpty { value = CellValue.raw(date: .init(start: .now)) } }
        case .number:
            TextField("Zahl", text: $value)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        case .text, .url, .checkbox:
            TextField("Text", text: $value)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }
    }
}

// MARK: - Sortieren

private struct SortEditor: View {
    let document: DatabaseDocument
    @Environment(\.dismiss) private var dismiss
    @State private var rules: [SortRule] = []

    var body: some View {
        NavigationStack {
            Form {
                ForEach(rules.indices, id: \.self) { index in
                    Section {
                        Picker("Feld", selection: $rules[index].field) {
                            ForEach(document.database.fields) { Text($0.name).tag($0.name) }
                        }
                        Picker("Richtung", selection: $rules[index].descending) {
                            Text("Aufsteigend (A → Z, 1 → 9, alt → neu)").tag(false)
                            Text("Absteigend (Z → A, 9 → 1, neu → alt)").tag(true)
                        }
                        Button("Sortierung entfernen", systemImage: "trash", role: .destructive) {
                            rules.remove(at: index)
                        }
                    } header: {
                        Text(index == 0 ? "Zuerst nach" : "Dann nach")
                    }
                }
                Section {
                    Button("Sortierung hinzufügen", systemImage: "plus") {
                        let unused = document.database.fields.first { field in !rules.contains { $0.field == field.name } }
                        if let field = unused ?? document.database.fields.first { rules.append(SortRule(field: field.name)) }
                    }
                } footer: {
                    Text("Ohne Sortierung gilt die Reihenfolge in der Datei. Leere Werte stehen immer am Ende.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Sortieren")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        document.updateView { $0.sorts = rules }
                        dismiss()
                    }
                }
            }
            .onAppear { rules = document.currentView.sorts ?? [] }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 380)
        #endif
    }
}
