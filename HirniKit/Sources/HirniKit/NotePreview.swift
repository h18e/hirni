import Foundation

/// Erzeugt die kurze Vorschau, die in der Notizliste unter dem Titel steht.
public enum NotePreview {
    public static let maxLength = 140

    public static func make(from text: String) -> String {
        var lines = text.components(separatedBy: .newlines)[...]

        // YAML-Kopf (--- … ---) überspringen
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines = lines.dropFirst()
            if let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
                lines = lines[lines.index(after: end)...]
            } else {
                lines = []
            }
        }

        let cleaned = lines
            .map(stripMarkup)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return cleaned.count > maxLength ? String(cleaned.prefix(maxLength)) + "…" : cleaned
    }

    /// Entfernt Markdown-Zeichen am Zeilenanfang: `# `, `- `, `- [ ] `, `> ` …
    private static func stripMarkup(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        let prefixes = ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "- ", "* ", "+ ", "> "]
        while s.hasPrefix("#") { s.removeFirst() }
        for prefix in prefixes where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
            break
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
