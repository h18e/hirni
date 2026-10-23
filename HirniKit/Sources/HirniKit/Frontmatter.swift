import Foundation

/// Der YAML-Kopf einer Notiz, wie Obsidian ihn verwendet:
///
/// ```
/// ---
/// angepinnt: true
/// ---
/// Eigentlicher Text …
/// ```
///
/// hirni liest und schreibt nur einfache `schlüssel: wert`-Zeilen. Alles
/// andere im Kopf bleibt unverändert stehen.
public enum Frontmatter {
    public static let pinnedKey = "angepinnt"

    /// Trennt den Kopf (ohne die `---`-Zeilen) vom übrigen Text.
    public static func split(_ text: String) -> (header: String?, body: String) {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return (nil, text) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let end = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
        }) else {
            return (nil, text)
        }
        let header = lines[1..<end].joined(separator: "\n")
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (header, body)
    }

    public static func join(header: String?, body: String) -> String {
        guard let header, !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return body
        }
        return "---\n\(header)\n---\n\(body)"
    }

    public static func value(_ key: String, in text: String) -> String? {
        guard let header = split(text).header else { return nil }
        for line in header.split(separator: "\n") {
            if let (k, v) = keyValue(line), k == key { return v }
        }
        return nil
    }

    /// Setzt `key` auf `value`, oder entfernt die Zeile bei `nil`. Bleibt der
    /// Kopf danach leer, verschwindet er ganz.
    public static func setting(_ key: String, to value: String?, in text: String) -> String {
        let (header, body) = split(text)
        var lines = header.map { $0.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) } ?? []
        let index = lines.firstIndex { keyValue(Substring($0))?.key == key }
        switch (index, value) {
        case (let i?, let value?): lines[i] = "\(key): \(value)"
        case (let i?, nil): lines.remove(at: i)
        case (nil, let value?): lines.append("\(key): \(value)")
        case (nil, nil): break
        }
        return join(header: lines.joined(separator: "\n"), body: body)
    }

    private static func keyValue(_ line: Substring) -> (key: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
            value = String(value.dropFirst().dropLast())
        }
        return key.isEmpty ? nil : (key, value)
    }
}
