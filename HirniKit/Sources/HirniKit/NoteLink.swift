import Foundation

/// Links auf andere Notizen: `[Einkauf](hirni://notiz?id=k3f9a2c1&pfad=Inbox/Einkauf.md)`.
///
/// Die Zielnotiz bekommt beim ersten Link eine feste Kennung im Kopf
/// (`hirni-id: k3f9a2c1`). Darum findet der Link sie auch, wenn sie umbenannt
/// oder verschoben wird, selbst im Finder oder auf einem anderen Gerät. Der
/// Pfad dient nur als Rückfallebene (Datei noch nicht aus iCloud geladen).
/// Mit `fest=1` bleibt die Beschriftung, sonst folgt sie dem Titel der Notiz.
public enum NoteLink {
    static let idKey = "hirni-id"
    public static let pattern = try! NSRegularExpression(pattern: #"\[([^\]\n]+)\]\((hirni://notiz\?[^)\s]+)\)"#)

    /// Ein Ziel für die Auswahl beim Einfügen.
    public struct Target: Identifiable, Hashable, Sendable {
        public let url: URL
        public let title: String
        /// Ordner, leer = oberste Ebene.
        public let folder: String
        public var id: URL { url }
    }

    static func label(_ title: String) -> String {
        title.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
    }

    static func address(id: String, path: String, fixed: Bool) -> String {
        var parts = URLComponents()
        parts.scheme = "hirni"
        parts.host = "notiz"
        parts.queryItems = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "pfad", value: path)]
            + (fixed ? [URLQueryItem(name: "fest", value: "1")] : [])
        return parts.url?.absoluteString ?? ""
    }

    private static func query(_ address: String, _ name: String) -> String? {
        URL(string: address).flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }

    public static func id(in url: URL) -> String? { query(url.absoluteString, "id") }
    public static func path(in url: URL) -> String? { query(url.absoluteString, "pfad") }
}

extension MarkdownSyntax {
    /// Die Adresse des ersten Notiz-Links in `text`.
    public static func linkAddress(_ text: String) -> String? {
        let ns = text as NSString
        return NoteLink.pattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 2)) }
    }
}

extension Vault {
    /// Alle Notizen und Datenbanken für die Auswahl, ausser `excluding` und Vorlagen.
    public func linkTargets(excluding note: URL?) -> [NoteLink.Target] {
        let templates = templatesURL
        return (allNoteURLs() + allDatabaseURLs())
            .filter { !$0.isInside(templates) && $0.standardizedFileURL != note?.standardizedFileURL }
            .map { url in
                let folder = relativePath(of: url.deletingLastPathComponent()) ?? ""
                return NoteLink.Target(url: url, title: Self.title(of: url), folder: folder)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Markdown für einen Link auf `note`. `label` = eigene Beschriftung, die
    /// dem Titel nicht folgt. Vergibt der Notiz nötigenfalls ihre Kennung.
    public func linkMarkdown(to note: URL, label: String? = nil) throws -> String {
        let id = try noteID(of: note)
        let path = relativePath(of: note) ?? note.lastPathComponent
        let text = label.map(NoteLink.label) ?? NoteLink.label(Self.title(of: note))
        return "[\(text)](\(NoteLink.address(id: id, path: path, fixed: label != nil)))"
    }

    /// Die Kennung der Notiz; fehlt sie, kommt sie in den Kopf. Das
    /// Änderungsdatum bleibt (wie beim Anpinnen).
    public func noteID(of note: URL) throws -> String {
        let text = try readNote(at: note)
        if let id = Frontmatter.value(NoteLink.idKey, in: text), !id.isEmpty { return id }
        let id = Row.newID()
        let updated = Frontmatter.setting(NoteLink.idKey, to: id, in: text)
        let modified = modificationDate(of: note)
        try Coordinated.write(note) { url in
            try Data(updated.utf8).write(to: url, options: .atomic)
            if let modified {
                try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path(percentEncoded: false))
            }
        }
        return id
    }

    /// Alle Kennungen im Hirni-Ordner. Bei Doppelten gewinnt die erste.
    func noteIDs() -> [String: URL] {
        var result: [String: URL] = [:]
        for url in allNoteURLs() + allDatabaseURLs() {
            if let id = Frontmatter.value(NoteLink.idKey, in: beginning(of: url)), result[id] == nil { result[id] = url }
        }
        return result
    }

    /// Die Notiz hinter einem Link: zuerst über die Kennung, sonst über den Pfad.
    public func resolve(link: URL) -> URL? {
        if let id = NoteLink.id(in: link), let url = noteIDs()[id] { return url }
        guard let path = NoteLink.path(in: link) else { return nil }
        let url = root.appending(path: path)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// Führt Beschriftung und Pfad der Links im Text nach (Ziel umbenannt oder
    /// verschoben). Eigene Beschriftungen (`fest=1`) bleiben.
    public func refreshingNoteLinks(in text: String) -> String {
        guard text.contains("hirni://notiz?id=") else { return text }
        let ids = noteIDs()
        let ns = text as NSString
        var result = text as NSString
        for match in NoteLink.pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let address = ns.substring(with: match.range(at: 2))
            guard let id = NoteLink.id(in: URL(string: address) ?? root), let target = ids[id],
                  let path = relativePath(of: target) else { continue }
            let fixed = address.contains("fest=1")
            let label = fixed ? ns.substring(with: match.range(at: 1)) : NoteLink.label(Self.title(of: target))
            result = result.replacingCharacters(in: match.range, with: "[\(label)](\(NoteLink.address(id: id, path: path, fixed: fixed)))") as NSString
        }
        return result as String
    }
}
