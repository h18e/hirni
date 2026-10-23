import Foundation

/// Beobachtet den hirni-Ordner in iCloud und meldet Änderungen, egal ob sie von
/// einem anderen Gerät, vom Finder oder von Claude kommen.
///
/// Nebenbei sorgt er dafür, dass alle Dateien auf dieses Gerät heruntergeladen
/// werden. Notizen sind klein, und so sind sie auch offline verfügbar.
final class VaultMonitor {
    private let query = NSMetadataQuery()
    private let onChange: () -> Void
    private var observers: [NSObjectProtocol] = []
    private var debounce: Task<Void, Never>?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
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
        for case let item as NSMetadataItem in query.results {
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent,
               let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
        query.enableUpdates()

        // iCloud meldet oft mehrere Änderungen kurz hintereinander.
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}
