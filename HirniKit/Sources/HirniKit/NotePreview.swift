import Foundation

/// Erzeugt die kurze Vorschau, die in der Notizliste unter dem Titel steht.
public enum NotePreview {
    public static let maxLength = 140

    public static func make(from text: String) -> String {
        var lines = replacingEmbeds(in: text).components(separatedBy: .newlines)[...]

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

    /// `![](_Anhänge/foto.jpg)` → `[Bild]`, ein `hirni-db`-Block →
    /// `[Datenbank: Ausgaben]`, damit die Vorschau lesbar bleibt.
    private static func replacingEmbeds(in text: String) -> String {
        let blocks = NSMutableString(string: text)
        for block in DatabaseEmbed.blocks(in: text).reversed() {
            let name = (block.database as NSString).lastPathComponent
            blocks.replaceCharacters(in: block.range, with: name.isEmpty ? "[Datenbank]" : "[Datenbank: \(name)]")
        }
        let text = blocks as String
        let result = NSMutableString(string: text)
        for embed in AttachmentLinks.embeds(in: text).reversed() {
            let label = switch AttachmentLinks.kind(of: embed.path) {
            case .image: "[Bild]"
            case .pdf: "[PDF]"
            case nil: "[Anhang]"
            }
            result.replaceCharacters(in: embed.range, with: label)
        }
        return result as String
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
