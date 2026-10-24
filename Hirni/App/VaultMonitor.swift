import Foundation

/// Beobachtet den hirni-Ordner in iCloud und meldet Änderungen, egal ob sie von
/// einem anderen Gerät, vom Finder oder von Claude kommen.
///
/// Nebenbei sorgt er dafür, dass alle Dateien auf dieses Gerät heruntergeladen
/// werden. Notizen sind klein, und so sind sie auch offline verfügbar.
/// Ausserdem meldet er Konflikte und laufende Downloads.
final class VaultMonitor {
    /// Was iCloud gerade über die Dateien weiss.
    struct Status: Equatable {
        /// Dateien mit Fassungen, die iCloud nicht zusammenführen konnte.
        var conflicted: Set<URL> = []
        /// Dateien, die gerade heruntergeladen werden, mit Fortschritt 0…1.
        var downloading: [URL: Double] = [:]
    }

    private let query = NSMetadataQuery()
    private let onChange: () -> Void
    private let onStatus: (Status) -> Void
    private var lastStatus = Status()
    private var observers: [NSObjectProtocol] = []
    private var debounce: Task<Void, Never>?

    init(onChange: @escaping () -> Void, onStatus: @escaping (Status) -> Void) {
        self.onChange = onChange
        self.onStatus = onStatus
    }

    func start() {
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)

        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: query, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.queryDidChange() }
            })
        }
        query.start()
    }

    func stop() {
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func queryDidChange() {
        query.disableUpdates()
        var status = Status()
        for case let item as NSMetadataItem in query.results {
            guard let url = (item.value(forAttribute: NSMetadataItemURLKey) as? URL)?.canonical else { continue }
            let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if downloadStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                let percent = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double ?? 0
                status.downloading[url] = percent / 100
            }
            if item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool == true {
                status.conflicted.insert(url)
            }
        }
        query.enableUpdates()
        if status != lastStatus {
            lastStatus = status
            onStatus(status)
        }

        // iCloud meldet oft mehrere Änderungen kurz hintereinander.
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}

extension URL {
    /// Einheitliche Form einer Datei-URL für Vergleiche. iOS liefert denselben
    /// Pfad mal mit, mal ohne `/private` davor.
    var canonical: URL {
        standardizedFileURL.resolvingSymlinksInPath()
    }
}
