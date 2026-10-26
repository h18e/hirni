import Foundation

/// Eine Datenbank-Ansicht mitten in einer Notiz, als Codeblock, der auch in
/// anderen Programmen lesbar bleibt:
///
/// ````
/// ```hirni-db
/// datenbank: Ausgaben
/// ansicht: Pro Monat
/// ```
/// ````
///
/// `datenbank` ist der Name der Datenbank (im Ordner der Notiz oder irgendwo
/// im hirni-Ordner) oder ein Pfad ab dem hirni-Ordner, z. B. `Privat/Ausgaben`.
/// `ansicht` ist optional, ohne gilt die erste Ansicht.
public struct DatabaseEmbed: Equatable, Sendable {
    public static let language = "hirni-db"

    public let database: String
    public let view: String?
    /// Der ganze Block mit beiden ```-Zeilen.
    public let range: NSRange
    /// Die schliessende ```-Zeile: Darunter erscheint die Ansicht.
    public let closingLine: NSRange

    /// Erkennt alle vollständigen `hirni-db`-Blöcke. Blöcke ohne `datenbank`
    /// zählen trotzdem (mit leerem Namen), damit der Editor einen Hinweis zeigt.
    public static func blocks(in text: String) -> [DatabaseEmbed] {
        let ns = text as NSString
        var result: [DatabaseEmbed] = []
        var open: (start: Int, values: [String: String], isEmbed: Bool)?

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines]) { line, range, _, _ in
            let trimmed = (line ?? "").trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let current = open {
                    if current.isEmbed {
                        result.append(DatabaseEmbed(
                            database: current.values["datenbank"] ?? "",
                            view: current.values["ansicht"].flatMap { $0.isEmpty ? nil : $0 },
                            range: NSRange(current.start..<NSMaxRange(range)),
                            closingLine: range
                        ))
                    }
                    open = nil
                } else {
                    let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
                    open = (range.location, [:], language == Self.language)
                }
                return
            }
            guard open?.isEmbed == true, let colon = trimmed.firstIndex(of: ":") else { return }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            open?.values[key] = value
        }
        return result
    }

    /// Der Block-Text für eine Datenbank, z. B. zum Einfügen.
    public static func markdown(database: String, view: String?) -> String {
        var lines = ["```\(language)", "datenbank: \(database)"]
        if let view, !view.isEmpty { lines.append("ansicht: \(view)") }
        lines.append("```")
        return lines.joined(separator: "\n")
    }
}

extension Vault {
    /// Findet die Datenbank zu `datenbank:` aus einem eingebetteten Block.
    /// Reihenfolge: Pfad ab dem hirni-Ordner, gleicher Ordner wie die Notiz,
    /// dann irgendwo im hirni-Ordner (der kürzeste Pfad gewinnt).
    public func resolveDatabase(_ reference: String, from note: URL) -> URL? {
        var name = reference.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if name.lowercased().hasSuffix(VaultLayout.databaseSuffix) {
            name = String(name.dropLast(VaultLayout.databaseSuffix.count))
        }
        let fileName = name + VaultLayout.databaseSuffix

        if name.contains("/") {
            let url = root.appending(path: fileName)
            return contains(url) && FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
        }
        let sibling = note.deletingLastPathComponent().appending(path: fileName)
        if FileManager.default.fileExists(atPath: sibling.path(percentEncoded: false)) { return sibling }

        return allDatabaseURLs()
            .filter { Self.title(of: $0).lowercased() == name.lowercased() }
            .min { $0.pathComponents.count != $1.pathComponents.count ? $0.pathComponents.count < $1.pathComponents.count : $0.path < $1.path }
    }

    /// Wie eine Notiz die Datenbank nennt: nur der Name, wenn beide im selben
    /// Ordner liegen, sonst der Pfad ab dem hirni-Ordner.
    public func databaseReference(for database: URL, from note: URL) -> String {
        if database.deletingLastPathComponent().standardizedFileURL == note.deletingLastPathComponent().standardizedFileURL {
            return Self.title(of: database)
        }
        guard let path = relativePath(of: database) else { return Self.title(of: database) }
        return String(path.dropLast(VaultLayout.databaseSuffix.count))
    }

    /// Alle Datenbanken, für die Auswahl «Datenbank einfügen».
    public func databases() -> [URL] {
        allDatabaseURLs()
    }
}
