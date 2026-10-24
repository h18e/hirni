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
                ForEach(edits) { edit in
                    FieldSection(edit: .element(edit.id, in: $edits, fallback: edit)) {
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
        if names.contains(where: { $0.lowercased() == "id" }) { return "«id» ist für hirni reserviert." }
        if Set(names.map { $0.lowercased() }).count != names.count { return "Zwei Felder haben denselben Namen." }
        if edits.isEmpty { return "Eine Datenbank braucht mindestens ein Feld." }
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
    let delete: () -> Void
    @State private var newOption = ""

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
                ForEach(edit.field.options ?? [], id: \.self) { option in
                    HStack {
                        Text(option)
                        Spacer()
                        Button("Entfernen", systemImage: "minus.circle") {
                            edit.field.options?.removeAll { $0 == option }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
                HStack {
                    TextField("Neue Option", text: $newOption)
                        .onSubmit(addOption)
                    Button("Hinzufügen", action: addOption)
                        .disabled(newOption.trimmingCharacters(in: .whitespaces).isEmpty)
                }
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
                if newType != .number { edit.field.format = nil }
                if newType != .date { edit.field.includesTime = nil }
                if newType == .select || newType == .multiSelect {
                    edit.field.options = edit.field.options ?? []
                } else {
                    edit.field.options = nil
                }
            }
        )
    }

    private func addOption() {
        let option = newOption.trimmingCharacters(in: .whitespaces)
        guard !option.isEmpty, !(edit.field.options ?? []).contains(option) else { return }
        edit.field.options = (edit.field.options ?? []) + [option]
        newOption = ""
    }
}
