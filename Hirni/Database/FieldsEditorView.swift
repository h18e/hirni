import HirniKit
import SwiftUI

/// Felder einer Datenbank verwalten: anlegen, umbenennen, Typ ändern,
/// Optionen pflegen, sortieren, löschen. Übernommen wird mit «Fertig».
struct FieldsEditorView: View {
    let document: DatabaseDocument
    @Environment(\.dismiss) private var dismiss

    @State private var edits: [FieldEdit] = []
    @State private var pendingLoss: Int?

    var body: some View {
        NavigationStack {
            Form {
                if edits.count > 1 {
                    Section {
                        ForEach(edits) { edit in
                            Label(edit.field.name.isEmpty ? "Ohne Namen" : edit.field.name, systemImage: edit.field.type.systemImage)
                        }
                        .onMove { edits.move(fromOffsets: $0, toOffset: $1) }
                    } header: {
                        Text("Reihenfolge")
                    } footer: {
                        #if os(iOS)
                        Text("Zum Verschieben ein Feld lange drücken und ziehen. Das erste Feld ist der Titel eines Eintrags.")
                        #else
                        Text("Zum Verschieben ein Feld ziehen. Das erste Feld ist der Titel eines Eintrags. In der Tabelle lassen sich auch die Spaltenüberschriften ziehen.")
                        #endif
                    }
                }
                ForEach(edits) { edit in
                    FieldSection(edit: .element(edit.id, in: $edits, fallback: edit),
                                 otherFields: edits.filter { $0.id != edit.id }.map(\.field)) {
                        edits.removeAll { $0.id == edit.id }
                    }
                }
                Section {
                    Button("Feld hinzufügen", systemImage: "plus") {
                        edits.append(FieldEdit(originalName: nil, field: Field(name: newFieldName, type: .text)))
                    }
                }
                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Felder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { finish() }
                        .disabled(problem != nil)
                }
            }
            .onAppear {
                edits = document.database.fields.map { FieldEdit(originalName: $0.name, field: $0) }
            }
            .confirmationDialog(
                "Dabei gehen \(pendingLoss ?? 0) Werte verloren",
                isPresented: Binding(get: { pendingLoss != nil }, set: { if !$0 { pendingLoss = nil } }),
                titleVisibility: .visible
            ) {
                Button("Trotzdem übernehmen", role: .destructive) { apply() }
            } message: {
                Text("Werte in gelöschten Feldern und Werte, die nicht zum neuen Typ oder den Optionen passen, werden geleert.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    /// Ungültige Eingaben, die «Fertig» verhindern.
    private var problem: String? {
        let names = edits.map { $0.field.name.trimmingCharacters(in: .whitespaces) }
        if names.contains(where: \.isEmpty) { return "Jedes Feld braucht einen Namen." }
        if names.contains(where: { $0.lowercased() == "id" }) { return "«id» ist für Hirni reserviert." }
        if Set(names.map { $0.lowercased() }).count != names.count { return "Zwei Felder haben denselben Namen." }
        if edits.isEmpty { return "Eine Datenbank braucht mindestens ein Feld." }
        for edit in edits {
            let options = edit.namedOptions
            if options.contains(where: \.isEmpty) { return "Im Feld «\(edit.field.name)» hat eine Option keinen Namen." }
            if Set(options).count != options.count { return "Im Feld «\(edit.field.name)» gibt es eine Option doppelt." }
        }
        if edits.contains(where: { ($0.field.options ?? []).contains { $0.contains(",") } && $0.field.type == .multiSelect }) {
            return "Optionen einer Mehrfachauswahl dürfen kein Komma enthalten."
        }
        return nil
    }

    private var newFieldName: String {
        var number = 1
        while edits.contains(where: { $0.field.name == (number == 1 ? "Feld" : "Feld \(number)") }) { number += 1 }
        return number == 1 ? "Feld" : "Feld \(number)"
    }

    private func finish() {
        let cleaned = edits.map { edit -> FieldEdit in
            var edit = edit
            edit.field.name = edit.field.name.trimmingCharacters(in: .whitespaces)
            // Neue, leer gelassene Optionen fallen weg.
            if let options = edit.field.options {
                let keep = options.indices.filter {
                    !options[$0].trimmingCharacters(in: .whitespaces).isEmpty || (edit.optionOrigins[safe: $0] ?? nil) != nil
                }
                edit.field.options = keep.map { options[$0].trimmingCharacters(in: .whitespaces) }
                edit.optionOrigins = keep.map { edit.optionOrigins[safe: $0] ?? nil }
            }
            return edit
        }
        edits = cleaned
        let loss = document.lostValues(applying: cleaned)
        if loss > 0 {
            pendingLoss = loss
        } else {
            apply()
        }
    }

    private func apply() {
        document.updateFields(edits)
        dismiss()
    }
}

private struct FieldSection: View {
    @Binding var edit: FieldEdit
    /// Die anderen Felder (für Formeln).
    var otherFields: [Field] = []
    let delete: () -> Void
    @FocusState private var focusedOption: Int?

    var body: some View {
        Section {
            TextField("Name", text: $edit.field.name)
            Picker("Typ", selection: type) {
                ForEach(FieldType.allCases, id: \.self) { type in
                    Label(type.label, systemImage: type.systemImage).tag(type)
                }
            }
            switch edit.field.type {
            case .number:
                Picker("Format", selection: Binding(
                    get: { edit.field.format ?? .plain },
                    set: { edit.field.format = $0 == .plain ? nil : $0 }
                )) {
                    ForEach(NumberFormat.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            case .date:
                Toggle("Mit Uhrzeit", isOn: Binding(
                    get: { edit.field.includesTime ?? false },
                    set: { edit.field.includesTime = $0 ? true : nil }
                ))
            case .select, .multiSelect:
                // Optionen direkt umbenennen; die Einträge wandern beim Übernehmen mit.
                ForEach(Array((edit.field.options ?? []).indices), id: \.self) { index in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(OptionColors.color(index))
                            .frame(width: 10, height: 10)
                        TextField("Option", text: option(at: index), prompt: Text("Name der Option"))
                            .labelsHidden()
                            .focused($focusedOption, equals: index)
                        Button("Option entfernen", systemImage: "minus.circle.fill") { removeOption(at: index) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                    }
                }
                Button("Option hinzufügen", systemImage: "plus.circle.fill", action: addOption)
                    .buttonStyle(.borderless)
            case .formula:
                FormulaEditor(field: $edit.field, otherFields: otherFields)
            case .text, .checkbox, .url:
                EmptyView()
            }
            Button("Feld löschen", systemImage: "trash", role: .destructive, action: delete)
        } header: {
            Text(edit.originalName == nil ? "Neues Feld" : edit.field.name)
        }
    }

    /// Beim Wechsel des Typs passende Zusatzangaben setzen bzw. entfernen.
    private var type: Binding<FieldType> {
        Binding(
            get: { edit.field.type },
            set: { newType in
                edit.field.type = newType
                if newType != .number && newType != .formula { edit.field.format = nil }
                if newType != .formula { edit.field.formula = nil }
                if newType != .date { edit.field.includesTime = nil }
                if newType == .select || newType == .multiSelect {
                    edit.field.options = edit.field.options ?? []
                } else {
                    edit.field.options = nil
                    edit.optionOrigins = []
                }
            }
        )
    }

    /// Neue, leere Option mit dem Cursor darin.
    private func addOption() {
        let options = edit.field.options ?? []
        edit.field.options = options + [""]
        edit.optionOrigins.append(nil)
        // Erst wenn die Zeile da ist, lässt sie sich fokussieren.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            focusedOption = options.count
        }
    }

    private func removeOption(at index: Int) {
        guard var options = edit.field.options, options.indices.contains(index) else { return }
        options.remove(at: index)
        edit.field.options = options
        if edit.optionOrigins.indices.contains(index) { edit.optionOrigins.remove(at: index) }
        focusedOption = nil
    }

    /// Über die Position, mit Schutz: Nach dem Entfernen darf ein altes
    /// Feld nicht mehr auf eine Option zugreifen, die es nicht mehr gibt.
    private func option(at index: Int) -> Binding<String> {
        Binding(
            get: { (edit.field.options ?? []).indices.contains(index) ? edit.field.options![index] : "" },
            set: { value in
                guard let options = edit.field.options, options.indices.contains(index) else { return }
                edit.field.options![index] = value
            }
        )
    }
}

private extension FieldEdit {
    /// Optionen ohne die neuen, noch leeren (die beim Übernehmen wegfallen).
    var namedOptions: [String] {
        let options = field.options ?? []
        return options.indices.compactMap { index in
            let name = options[index].trimmingCharacters(in: .whitespaces)
            return name.isEmpty && (optionOrigins[safe: index] ?? nil) == nil ? nil : name
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Formel eines Felds: Ausdruck, Felder zum Einfügen, Format, Prüfung.
private struct FormulaEditor: View {
    @Binding var field: Field
    let otherFields: [Field]

    private var formula: Binding<String> {
        Binding(get: { field.formula ?? "" }, set: { field.formula = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        TextField("Formel", text: formula, prompt: Text("z. B. [Preis] * [Menge]"), axis: .vertical)
            .font(.body.monospaced())
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
        if let problem = Formula.check(field.formula ?? "", fields: otherFields + [field]), !(field.formula ?? "").isEmpty {
            Label(problem, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.callout)
        }
        Menu("Feld einfügen", systemImage: "plus.square.on.square") {
            ForEach(otherFields) { other in
                Button(other.name, systemImage: other.type.systemImage) {
                    let current = field.formula ?? ""
                    field.formula = current + (current.isEmpty || current.hasSuffix(" ") ? "" : " ") + "[\(other.name)]"
                }
            }
        }
        Menu("Funktion einfügen", systemImage: "function") {
            ForEach(Self.functions, id: \.self) { function in
                Button(function) {
                    let current = field.formula ?? ""
                    field.formula = current + (current.isEmpty || current.hasSuffix(" ") ? "" : " ") + function
                }
            }
        }
        Picker("Format", selection: Binding(
            get: { field.format ?? .plain },
            set: { field.format = $0 == .plain ? nil : $0 }
        )) {
            ForEach(NumberFormat.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Text("Rechnen mit + − * / und Klammern, Text verbinden mit &, vergleichen mit = <> < >. SUMME([Feld]) rechnet über die ganze Spalte. Alle Funktionen: Hilfe → Datenbanken.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    static let functions = [
        "SUMME()", "MITTELWERT()", "ANZAHL()", "MIN()", "MAX()", "RUNDEN(; 2)", "ABS()",
        "WENN(; ; )", "UND()", "ODER()", "NICHT()", "HEUTE()", "TAGE(; )", "JAHR()", "MONAT()", "LÄNGE()", "ISTLEER()",
    ]
}
