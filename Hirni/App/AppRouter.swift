import Foundation
import HirniKit
import WidgetKit

/// Wohin die App springen soll: aus einer Mitteilung, dem Widget
/// (`hirni://…`) oder einem Kurzbefehl.
enum AppDestination: Equatable {
    case tasks
    /// Notiz, Pfad ab dem Hirni-Ordner.
    case note(String)

    /// `hirni://pendenzen`, `hirni://notiz?pfad=Inbox/Einkauf.md`
    init?(url: URL) {
        guard url.scheme == "hirni" else { return nil }
        switch url.host() {
        case "pendenzen": self = .tasks
        case "notiz":
            guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "pfad" })?.value else { return nil }
            self = .note(path)
        default: return nil
        }
    }
}

/// Leitet Sprünge an die Bibliothek weiter; kommen sie, bevor sie bereit ist
/// (App wird gerade gestartet), werden sie aufbewahrt.
final class AppRouter {
    static let shared = AppRouter()

    private var pending: AppDestination?
    var handler: ((AppDestination) -> Void)? {
        didSet {
            if let pending, let handler {
                self.pending = nil
                handler(pending)
            }
        }
    }

    func open(_ destination: AppDestination) {
        if let handler { handler(destination) } else { pending = destination }
    }
}

/// Die Daten fürs Widget im gemeinsamen App-Gruppen-Ordner.
enum WidgetData {
    /// Speichert und lässt das Widget neu zeichnen, wenn sich etwas geändert hat.
    nonisolated static func publish(_ snapshot: WidgetSnapshot) {
        guard let folder = AppGroup.folder,
              WidgetSnapshot.load(from: folder) != snapshot
        else { return }
        try? snapshot.save(to: folder)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Nach einer Änderung ausserhalb der laufenden App (Kurzbefehl).
    nonisolated static func publish(from vault: Vault) {
        publish(WidgetSnapshot.make(tasks: vault.allTasks(), dueDates: vault.dueDates(), in: vault))
    }
}
