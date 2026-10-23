import Foundation

/// Dateizugriffe über `NSFileCoordinator`.
///
/// iCloud Drive (und Programme wie der Finder oder Claude) greifen gleichzeitig
/// auf dieselben Dateien zu. Der Koordinator sorgt dafür, dass niemand eine
/// halb geschriebene Datei liest und dass iCloud Verschiebungen mitbekommt.
/// Ein koordiniertes Lesen lädt eine noch nicht heruntergeladene Datei
/// ausserdem automatisch herunter.
enum Coordinated {
    static func read<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url, options: [], error: &coordinationError
        ) { url in
            result = Result { try body(url) }
        }
        if let coordinationError { throw coordinationError }
        return try result!.get()
    }

    static func write<T>(
        _ url: URL,
        options: NSFileCoordinator.WritingOptions = [],
        _ body: (URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: options, error: &coordinationError
        ) { url in
            result = Result { try body(url) }
        }
        if let coordinationError { throw coordinationError }
        return try result!.get()
    }

    static func move(from source: URL, to destination: URL, fileManager: FileManager = .default) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(
            writingItemAt: source, options: .forMoving,
            writingItemAt: destination, options: .forReplacing,
            error: &coordinationError
        ) { source, destination in
            result = Result {
                coordinator.item(at: source, willMoveTo: destination)
                try fileManager.moveItem(at: source, to: destination)
                coordinator.item(at: source, didMoveTo: destination)
            }
        }
        if let coordinationError { throw coordinationError }
        try result!.get()
    }

    static func delete(_ url: URL, fileManager: FileManager = .default) throws {
        try write(url, options: .forDeleting) { url in
            try fileManager.removeItem(at: url)
        }
    }
}
