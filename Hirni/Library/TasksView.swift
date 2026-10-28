import HirniKit
import SwiftUI

/// Alle Checkboxen aus allen Notizen: offene nach Kategorie (erster Tag der
/// Zeile, darin nach Stichtag), darunter die erledigten. Abhaken ändert die
/// Notiz selbst; der Stichtag steht nur in `_Hirni/Pendenzen.json`.
struct TasksView: View {
    @Environment(VaultStore.self) private var store
    /// Gewählte Pendenz; öffnet ihre Notiz.
    @State private var selection: String?
    @State private var newCategoryFor: TaskItem?
    @State private var newCategory = ""
    @State private var showsDone = true
    /// Pendenz, deren Stichtag gerade gesetzt wird.
    @State private var dueFor: TaskItem?
    /// Pendenz, die nach Rückfrage gelöscht wird.
    @State private var deleting: TaskItem?

    var body: some View {
        let open = store.tasks.filter { !$0.isDone }
        let done = store.tasks.filter(\.isDone).sorted { ($0.done ?? .distantPast) > ($1.done ?? .distantPast) }
        List(selection: $selection) {
            ForEach(groups(open), id: \.name) { group in
                Section {
                    ForEach(group.tasks) { task in row(task) }
                } header: {
                    Text("\(group.name) · \(group.tasks.count)")
                }
            }
            if !done.isEmpty {
                Section(isExpanded: $showsDone) {
                    ForEach(done) { task in row(task) }
                } header: {
                    Text("Erledigte Pendenzen · \(done.count)")
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.sidebar)
        #endif
        .overlay {
            if store.tasks.isEmpty {
                ContentUnavailableView(
                    "Keine Pendenzen",
                    systemImage: "checklist",
                    description: Text("Checkboxen aus allen Notizen erscheinen hier. Mit #tag in der Zeile bekommen sie eine Kategorie.")
                )
            }
        }
        .navigationTitle("Pendenzen")
        .sheet(item: $dueFor) { task in DueDateSheet(task: task) }
        .confirmationDialog(
            "Pendenz löschen?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { task in
            Button("Löschen", role: .destructive) { Task { await store.deleteTask(task) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { task in
            Text("«\(task.text)» wird aus der Notiz «\(Vault.title(of: task.note))» entfernt.")
        }
        #if os(macOS)
        .onDeleteCommand {
            if let selection, let task = store.tasks.first(where: { $0.id == selection }) { deleting = task }
        }
        #endif
        .onChange(of: selection) { _, id in
            guard let id, let task = store.tasks.first(where: { $0.id == id }) else { return }
            store.selectedNote = task.note
        }
        .onChange(of: store.selectedNote) { _, note in
            if note == nil { selection = nil }
        }
        .alert("Neue Kategorie", isPresented: Binding(get: { newCategoryFor != nil }, set: { if !$0 { newCategoryFor = nil } })) {
            TextField("Name", text: $newCategory)
            Button("Abbrechen", role: .cancel) {}
            Button("Übernehmen") {
                let name = newCategory.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                if let task = newCategoryFor, !name.isEmpty { Task { await store.setTaskCategory(task, name) } }
                newCategory = ""
            }
        } message: {
            Text("Wird als #tag in die Zeile geschrieben.")
        }
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                Task { await store.setTask(task, done: !task.isDone) }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(task.isDone ? "Wieder öffnen" : "Abhaken")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.text)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                    Text(Vault.title(of: task.note))
                    if task.isDone, let done = task.done {
                        Text("· erledigt " + Self.format(done))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if !task.isDone, let due = store.dueDate(of: task) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text("fällig " + Self.format(due))
                    }
                    .font(.caption.weight(isOverdue(due) ? .semibold : .regular))
                        .foregroundStyle(isOverdue(due) ? Color.red : .secondary)
                }
            }
        }
        .tag(task.id)
        .contextMenu { menu(task) }
        #if os(iOS)
        .swipeActions(edge: .leading) {
            Button(task.isDone ? "Öffnen" : "Erledigt", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark") {
                Task { await store.setTask(task, done: !task.isDone) }
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button("Löschen", systemImage: "trash") { deleting = task }
                .tint(.red)
        }
        #endif
    }

    @ViewBuilder
    private func menu(_ task: TaskItem) -> some View {
        Button(task.isDone ? "Wieder öffnen" : "Erledigt", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark") {
            Task { await store.setTask(task, done: !task.isDone) }
        }
        Button("Notiz öffnen", systemImage: "note.text") { selection = task.id }
        if !task.isDone {
            Button(store.dueDate(of: task) == nil ? "Stichtag …" : "Stichtag ändern …", systemImage: "calendar") { dueFor = task }
            if store.dueDate(of: task) != nil {
                Button("Stichtag entfernen", systemImage: "calendar.badge.minus") {
                    Task { await store.setDueDate(nil, for: task) }
                }
            }
        }
        Menu("Kategorie", systemImage: "tag") {
            ForEach(store.tags, id: \.self) { tag in
                Button(tag) { Task { await store.setTaskCategory(task, tag) } }
            }
            Divider()
            Button("Neue Kategorie …", systemImage: "plus") { newCategoryFor = task }
            if task.category != nil {
                Button("Ohne Kategorie", systemImage: "tag.slash") { Task { await store.setTaskCategory(task, nil) } }
            }
        }
        Divider()
        Button("Löschen …", systemImage: "trash", role: .destructive) { deleting = task }
    }

    /// Offene Pendenzen nach Kategorie, alphabetisch, «Ohne Kategorie» zuletzt.
    /// Innerhalb einer Kategorie die ältesten zuerst.
    private func groups(_ tasks: [TaskItem]) -> [(name: String, tasks: [TaskItem])] {
        let grouped = Dictionary(grouping: tasks) { $0.category.map { "#" + $0 } ?? "Ohne Kategorie" }
        return grouped.keys
            .sorted { a, b in
                if a == "Ohne Kategorie" { return false }
                if b == "Ohne Kategorie" { return true }
                return a.localizedStandardCompare(b) == .orderedAscending
            }
            .map { key in (key, grouped[key]!.sorted { (store.dueDate(of: $0) ?? .distantFuture) < (store.dueDate(of: $1) ?? .distantFuture) }) }
    }

    private static func format(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "de_CH")).weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Überfällig: Stichtag vor heute.
    private func isOverdue(_ date: Date) -> Bool {
        date < Calendar.current.startOfDay(for: .now)
    }
}

/// Stichtag wählen: Kalender, Übernehmen.
private struct DueDateSheet: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(task.text).font(.headline)
                }
                DatePicker("Stichtag", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "de_CH"))
            }
            .navigationTitle("Stichtag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        Task { await store.setDueDate(date, for: task) }
                        dismiss()
                    }
                }
            }
            .onAppear { date = store.dueDate(of: task) ?? .now }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 440)
        #endif
    }
}
