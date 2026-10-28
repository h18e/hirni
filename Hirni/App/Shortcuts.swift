import AppIntents
import HirniKit

/// Kurzbefehle und Siri: Notiz oder Pendenz erfassen, ohne Hirni zu öffnen.
struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Neue Notiz"
    static let description = IntentDescription("Legt in Hirni eine Notiz in der Inbox an. Die erste Zeile wird zum Titel.")

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Neue Notiz \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let vault = try await QuickCapture.vault()
        let text = text
        let note = try await Task.detached { try vault.quickNote(text) }.value
        return .result(dialog: "Notiz «\(Vault.title(of: note))» ist in der Inbox.")
    }
}

struct NewTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Neue Pendenz"
    static let description = IntentDescription("Hängt in Hirni eine offene Pendenz an die Notiz «Pendenzen» in der Inbox an.")

    @Parameter(title: "Pendenz")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Neue Pendenz \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let vault = try await QuickCapture.vault()
        let text = text
        try await Task.detached {
            try vault.quickTask(text)
            WidgetData.publish(from: vault)
        }.value
        return .result(dialog: "Pendenz «\(text)» ist notiert.")
    }
}

struct OpenTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Pendenzen zeigen"
    static let description = IntentDescription("Öffnet Hirni mit der Liste der Pendenzen.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await AppRouter.shared.open(.tasks)
        return .result()
    }
}

struct HirniShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewNoteIntent(),
            phrases: ["Neue Notiz in \(.applicationName)", "Notiz in \(.applicationName) erfassen"],
            shortTitle: "Neue Notiz",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: NewTaskIntent(),
            phrases: ["Neue Pendenz in \(.applicationName)", "Pendenz in \(.applicationName) erfassen"],
            shortTitle: "Neue Pendenz",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: OpenTasksIntent(),
            phrases: ["Pendenzen in \(.applicationName) zeigen", "Meine Pendenzen in \(.applicationName)"],
            shortTitle: "Pendenzen",
            systemImageName: "list.bullet"
        )
    }
}

enum QuickCapture {
    struct Unavailable: LocalizedError {
        var errorDescription: String? { "Hirni findet seinen Ordner in iCloud Drive nicht." }
    }

    static func vault() async throws -> Vault {
        let root = try await Task.detached {
            guard let root = VaultLocator.findRoot() else { throw Unavailable() }
            try VaultLayout.prepare(root: root)
            return root
        }.value
        return Vault(root: root)
    }
}
