import Foundation

/// Offene Notizen als Tabs, wie im Browser: Eine normal geöffnete Notiz
/// ersetzt den aktiven Tab, ein neuer Tab entsteht nur auf Wunsch.
public struct NoteTabs: Equatable, Sendable {
    public private(set) var urls: [URL]
    /// Der Tab, den die nächste normal geöffnete Notiz ersetzt.
    public private(set) var active: URL?

    public init(urls: [URL] = [], active: URL? = nil) {
        self.urls = urls
        self.active = active.flatMap { urls.contains($0) ? $0 : nil } ?? urls.last
    }

    /// Normal geöffnet: In ihrem Tab zeigen, sonst den aktiven Tab ersetzen.
    public mutating func show(_ url: URL) {
        if !urls.contains(url) {
            if let active, let position = urls.firstIndex(of: active) {
                urls[position] = url
            } else {
                urls.append(url)
            }
        }
        active = url
    }

    /// «In neuem Tab öffnen». Der aktive Tab bleibt erhalten.
    public mutating func openNew(_ url: URL) {
        if !urls.contains(url) { urls.append(url) }
        active = url
    }

    /// Schliesst einen Tab. Gibt den Nachbarn zurück, der an seine Stelle rückt.
    @discardableResult
    public mutating func close(_ url: URL) -> URL? {
        guard let position = urls.firstIndex(of: url) else { return nil }
        urls.remove(at: position)
        let neighbour = position < urls.count ? urls[position] : urls.last
        if active == url { active = neighbour }
        return neighbour
    }

    /// Notiz umbenannt: Der Tab bleibt an seinem Platz.
    public mutating func replace(_ old: URL, with new: URL) {
        guard let position = urls.firstIndex(of: old) else { return }
        urls[position] = new
        if active == old { active = new }
    }

    /// Entfernt Tabs, deren Datei es nicht mehr gibt.
    public mutating func retain(where isKept: (URL) -> Bool) {
        for url in urls where !isKept(url) { close(url) }
    }
}
