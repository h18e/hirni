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

    private(set) var state: State
    private var isLocating = false
    /// Der Ordner wurde in diesem Programmlauf bei iCloud nachgefragt.
    private var isVerified = false

    /// Wo der hirni-Ordner beim letzten Mal lag. Gibt es ihn noch, startet
    /// Hirni sofort damit (samt der gemerkten Vorschau, siehe `VaultSnapshot`)
    /// und fragt iCloud im Hintergrund nach.
    private static let lastRootKey = "letzterHirniOrdner"

    init() {
        if let path = UserDefaults.standard.string(forKey: Self.lastRootKey),
           FileManager.default.fileExists(atPath: path) {
            state = .ready(URL(filePath: path, directoryHint: .isDirectory))
        } else {
            state = .searching
        }
    }

    /// Der hirni-Ordner, ohne ihn vorzubereiten. Nicht auf dem Hauptthread
    /// aufrufen: Beim ersten Mal kann das einige Sekunden dauern.
    nonisolated static func findRoot() -> URL? {
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) {
            return container.appending(path: "Documents", directoryHint: .isDirectory)
        }
        #if targetEnvironment(simulator)
        // Im Simulator ist meist kein iCloud angemeldet. Damit sich die
        // Oberfläche trotzdem testen lässt: lokaler Ordner in der App.
        return URL.documentsDirectory.appending(path: "hirni", directoryHint: .isDirectory)
        #else
        return nil
        #endif
    }

    /// Jedes Fenster ruft das auf. Ist der Ordner gefunden, bleibt alles, wie
    /// es ist, sonst würden die offenen Fenster neu aufgebaut.
    func locate() async {
        guard !isVerified, !isLocating else { return }
        isLocating = true
        defer { isLocating = false }
        let cached: URL? = if case .ready(let url) = state { url } else { nil }
        if cached == nil { state = .searching }
        // Apple verlangt, dass dieser Aufruf nicht auf dem Hauptthread passiert:
        // Beim ersten Mal kann er einige Sekunden dauern.
        let result: State = await Task.detached {
            guard let root = Self.findRoot() else { return .iCloudUnavailable }
            do {
                try VaultLayout.prepare(root: root)
                return .ready(root)
            } catch {
                return .failed(error.localizedDescription)
            }
        }.value
        isVerified = true
        if case .ready(let root) = result {
            UserDefaults.standard.set(root.path(percentEncoded: false), forKey: Self.lastRootKey)
            // Gleicher Ordner wie gemerkt: nichts neu aufbauen.
            if root.standardizedFileURL == cached?.standardizedFileURL { return }
        }
        state = result
    }
}
