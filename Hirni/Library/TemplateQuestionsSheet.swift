import HirniKit
import SwiftUI

/// Rückfragen einer Vorlage beim Anlegen: `{{frage: …}}` als Textfeld,
/// `{{wahl: A|B}}` als Auswahl. «Anlegen» füllt die Antworten überall ein.
struct TemplateQuestionsSheet: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let asking: VaultStore.AskingTemplate
    @State private var answers: [String: String] = [:]
    @FocusState private var focused: String?

    var body: some View {
        NavigationStack {
            Form {
                ForEach(asking.questions) { question in
                    if question.options.isEmpty {
                        Section(question.prompt) {
                            TextField(question.prompt, text: binding(question))
                                .focused($focused, equals: question.id)
                                .onSubmit(focusNext)
                        }
                    } else {
                        Picker(question.prompt, selection: binding(question)) {
                            ForEach(question.options, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Neue Notiz")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Anlegen", action: create) }
            }
            .onAppear {
                // Auswahl: erste Möglichkeit vorbelegen.
                for question in asking.questions where !question.options.isEmpty {
                    answers[question.id] = answers[question.id] ?? question.options.first
                }
                focused = asking.questions.first { $0.options.isEmpty }?.id
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 300)
        #endif
    }

    private func binding(_ question: TemplateQuestion) -> Binding<String> {
        Binding(get: { answers[question.id] ?? "" }, set: { answers[question.id] = $0 })
    }

    /// Eingabetaste: zur nächsten Frage, nach der letzten anlegen.
    private func focusNext() {
        let free = asking.questions.filter { $0.options.isEmpty }.map(\.id)
        if let current = focused, let index = free.firstIndex(of: current), index + 1 < free.count {
            focused = free[index + 1]
        } else {
            create()
        }
    }

    private func create() {
        let answers = answers
        let template = asking.url
        dismiss()
        Task { await store.newNote(template: template, answers: answers) }
    }
}
