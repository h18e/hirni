import HirniKit
import SwiftUI

/// Alle Checkboxen aus allen Notizen: offene nach Kategorie (erster Tag der
/// Zeile), darunter die erledigten. Abhaken ändert die Notiz selbst.
struct TasksView: View {
    @Environment(VaultStore.self) private var store
    /// Gewählte Pendenz; öffnet ihre Notiz.
    @State private var selection: String?
    @State private var newCategoryFor: TaskItem?
    @State private var newCategory = ""
    @State private var showsDone = true

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
                    if let date = task.isDone ? task.done : task.created {
                        Text("·")
                        Text((task.isDone ? "erledigt " : "erfasst ") + date.formatted(.dateTime.locale(Locale(identifier: "de_CH")).day().month(.abbreviated).year()))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
        #endif
    }

    @ViewBuilder
    private func menu(_ task: TaskItem) -> some View {
        Button(task.isDone ? "Wieder öffnen" : "Erledigt", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark") {
            Task { await store.setTask(task, done: !task.isDone) }
        }
        Button("Notiz öffnen", systemImage: "note.text") { selection = task.id }
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
            .map { key in (key, grouped[key]!.sorted { ($0.created ?? .distantFuture) < ($1.created ?? .distantFuture) }) }
    }
}
