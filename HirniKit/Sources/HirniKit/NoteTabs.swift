import Foundation

/// Die offenen Notizen als Tabs (iPhone): Jede geöffnete Notiz bekommt einen
/// Tab. Sind es zu viele, fällt der älteste weg, die Notiz selbst bleibt.
public struct NoteTabs: Equatable, Sendable {
    public static let limit = 6

    public private(set) var urls: [URL]

    public init(urls: [URL] = []) {
        self.urls = Array(urls.suffix(Self.limit))
    }

    public mutating func open(_ url: URL) {
        guard !urls.contains(url) else { return }
        urls.append(url)
        if urls.count > Self.limit { urls.removeFirst() }
    }

    /// Schliesst einen Tab. Gibt den Nachbarn zurück, der an seine Stelle rückt.
    @discardableResult
    public mutating func close(_ url: URL) -> URL? {
        guard let position = urls.firstIndex(of: url) else { return nil }
        urls.remove(at: position)
        return position < urls.count ? urls[position] : urls.last
    }

    /// Notiz umbenannt: Der Tab bleibt an seinem Platz.
    public mutating func replace(_ old: URL, with new: URL) {
        guard let position = urls.firstIndex(of: old) else { return }
        urls[position] = new
    }

    /// Entfernt Tabs, deren Datei es nicht mehr gibt.
    public mutating func retain(where isKept: (URL) -> Bool) {
        urls.removeAll { !isKept($0) }
    }
}
