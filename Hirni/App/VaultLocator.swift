import Foundation
import HirniKit
import Observation

/// Findet den hirni-Ordner in iCloud Drive und bereitet ihn vor.
///
/// Der Ordner ist der `Documents`-Unterordner des iCloud-Containers
/// `iCloud.ch.hebera.hirni`. Dank `NSUbiquitousContainers` in Config/Info.plist
/// erscheint er in der Dateien-App und im Finder als «iCloud Drive → hirni».
@Observable
final class VaultLocator {
    nonisolated static let containerIdentifier = "iCloud.ch.hebera.hirni"

    nonisolated enum State: Sendable {
        case searching
        case ready(URL)
        /// Kein iCloud-Konto angemeldet oder iCloud Drive für hirni ausgeschaltet.
        case iCloudUnavailable
        case failed(String)
    }

    private(set) var state: State = .searching

    func locate() async {
        state = .searching
        // Apple verlangt, dass dieser Aufruf nicht auf dem Hauptthread passiert:
        // Beim ersten Mal kann er einige Sekunden dauern.
        let result: State = await Task.detached {
            let root: URL
            if let container = FileManager.default.url(
                forUbiquityContainerIdentifier: Self.containerIdentifier
            ) {
                root = container.appending(path: "Documents", directoryHint: .isDirectory)
            } else {
                #if targetEnvironment(simulator)
                // Im Simulator ist meist kein iCloud angemeldet. Damit sich die
                // Oberfläche trotzdem testen lässt: lokaler Ordner in der App.
                root = URL.documentsDirectory.appending(path: "hirni", directoryHint: .isDirectory)
                #else
                return .iCloudUnavailable
                #endif
            }
            do {
                try VaultLayout.prepare(root: root)
                return .ready(root)
            } catch {
                return .failed(error.localizedDescription)
            }
        }.value
        state = result
    }
}
