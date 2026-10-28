#if os(macOS)
import AppKit
import HirniKit
import SwiftUI

/// Hirni in der Menüleiste: schnell eine Notiz oder Pendenz erfassen und
/// offene Pendenzen abhaken, ohne das Hirni-Fenster zu öffnen.
struct MenuBarQuickNote: View {
    enum Kind: String, CaseIterable {
        case note = "Notiz"
        case task = "Pendenz"
    }

    @Environment(VaultLocator.self) private var locator
    @Environment(\.openWindow) private var openWindow
    @AppStorage("menueleisteArt") private var kind = Kind.note
    @State private var text = ""
    @State private var saved: String?
    @State private var error: String?
    @State private var snapshot = WidgetSnapshot()
    @FocusState private var focused: Bool

    private var vault: Vault? {
        if case .ready(let url) = locator.state { Vault(root: url) } else { nil }
    }

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Art", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch kind {
            case .note:
                TextEditor(text: $text)
                    .font(.body)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(height: 110)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Erste Zeile wird zum Titel")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .allowsHitTesting(false)
                        }
                    }
            case .task:
                TextField("z. B. Velo flicken #haus", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { Task { await save() } }
            }

            HStack {
                if let saved {
                    Label(saved, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                        .lineLimit(1)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                        .lineLimit(2)
                }
                Spacer()
                Button(kind == .note ? "In Inbox sichern" : "Pendenz erfassen") { Task { await save() } }
                    .keyboardShortcut(.return, modifiers: kind == .note ? .command : [])
                    .buttonStyle(.borderedProminent)
                    .disabled(isEmpty || vault == nil)
            }

            if !snapshot.items.isEmpty {
                Divider()
                HStack {
                    Text("Offene Pendenzen").font(.headline)
                    Spacer()
                    Text("\(snapshot.openCount)").foregroundStyle(.secondary).monospacedDigit()
                }
                ForEach(snapshot.items.prefix(6)) { item in
                    taskRow(item)
                }
            }

            Divider()
            HStack {
                Button("Hirni öffnen") { showMainWindow() }
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 340)
        .task {
            if case .searching = locator.state { await locator.locate() }
            snapshot = AppGroup.folder.flatMap(WidgetSnapshot.load) ?? WidgetSnapshot()
            focused = true
        }
        .onChange(of: kind) { focused = true }
    }

    private func taskRow(_ item: WidgetSnapshot.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button {
                Task { await complete(item) }
            } label: {
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Erledigt")
            VStack(alignment: .leading, spacing: 0) {
                Text(item.text).lineLimit(1)
                Text(item.dueDate.map { "\(item.note) · fällig \(dueText($0))" } ?? item.note)
                    .font(.caption)
                    .foregroundStyle(isOverdue(item) ? .red : .secondary)
                    .lineLimit(1)
            }
        }
    }

    private func dueText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "heute" }
        if Calendar.current.isDateInTomorrow(date) { return "morgen" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func isOverdue(_ item: WidgetSnapshot.Item) -> Bool {
        guard let date = item.dueDate else { return false }
        return date < Calendar.current.startOfDay(for: .now)
    }

    private func save() async {
        guard let vault, !isEmpty else { return }
        let text = text
        let kind = kind
        do {
            let note = try await Task.detached {
                kind == .note ? try vault.quickNote(text) : try vault.quickTask(text)
            }.value
            self.text = ""
            error = nil
            saved = kind == .note ? "«\(Vault.title(of: note))» in der Inbox" : "Pendenz notiert"
            focused = true
            try? await Task.sleep(for: .seconds(3))
            saved = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func complete(_ item: WidgetSnapshot.Item) async {
        guard let vault else { return }
        let id = item.id
        let done = (try? await Task.detached { try vault.completeTask(key: id) }.value) == true
        if done {
            snapshot.complete(id)
        } else {
            error = "Die Pendenz wurde inzwischen geändert."
        }
    }

    /// Das bestehende Hauptfenster nach vorne holen, sonst ein neues öffnen.
    private func showMainWindow() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

/// Einstellungen (⌘,): Menüleisten-Symbol ein- oder ausblenden.
struct HirniSettings: View {
    @AppStorage("menueleisteAnzeigen") private var showsMenuBarExtra = true

    var body: some View {
        Form {
            Toggle("Hirni in der Menüleiste zeigen", isOn: $showsMenuBarExtra)
            Text("Über das Symbol in der Menüleiste erfasst du schnell eine Notiz oder Pendenz und hakst offene Pendenzen ab.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
#endif
