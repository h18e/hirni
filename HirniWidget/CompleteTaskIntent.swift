import AppIntents
import HirniKit
import WidgetKit

/// Abhaken direkt im Widget, ohne Hirni zu öffnen. Läuft im Widget selbst:
/// schreibt in die Notiz in iCloud Drive; geht das nicht, merkt es sich die
/// Pendenz im gemeinsamen Ordner, und Hirni hakt sie beim nächsten Öffnen ab.
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Pendenz erledigen"
    static let isDiscoverable = false

    @Parameter(title: "Pendenz")
    var id: String

    init() {}

    init(id: String) {
        self.id = id
    }

    func perform() async throws -> some IntentResult {
        let id = id
        await Task.detached { Self.complete(id) }.value
        return .result()
    }

    nonisolated private static func complete(_ id: String) {
        var written = false
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.ch.hebera.hirni") {
            let vault = Vault(root: container.appending(path: "Documents", directoryHint: .isDirectory))
            written = (try? vault.completeTask(key: id)) == true
        }
        guard let folder = AppGroup.folder else { return }
        if !written { try? WidgetCompletions.add(id, in: folder) }
        // Gleich aus der Anzeige nehmen; die App schreibt später den neuen Stand.
        if var snapshot = WidgetSnapshot.load(from: folder) {
            snapshot.complete(id)
            try? snapshot.save(to: folder)
        }
    }
}
