import Foundation

/// Ein eingebetteter Anhang im Text: `![Beschreibung](_Anhänge/foto.jpg)`.
public struct EmbedLink: Equatable, Sendable {
    /// Bereich des ganzen `![…](…)`.
    public let range: NSRange
    public let altText: String
    /// Pfad relativ zur Notiz, bereits entschlüsselt (`%20` → Leerzeichen).
    public let path: String
}

/// Lesen und Schreiben der Markdown-Verweise auf Anhänge.
///
/// hirni schreibt Standard-Markdown `![](_Anhänge/name.jpg)`, damit auch
/// Obsidian und andere Programme die Bilder anzeigen.
public enum AttachmentLinks {
    public enum Kind: Sendable {
        case image
        case pdf
    }

    public static func embeds(in text: String) -> [EmbedLink] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            var raw = ns.substring(with: m.range(at: 2))
            if raw.hasPrefix("<"), raw.hasSuffix(">") { raw = String(raw.dropFirst().dropLast()) }
            return EmbedLink(
                range: m.range,
                altText: ns.substring(with: m.range(at: 1)),
                path: raw.removingPercentEncoding ?? raw
            )
        }
    }

    /// Markdown zum Einfügen, z. B. `![](_Anhänge/foto-1.jpg)`.
    public static func markdown(for relativePath: String, altText: String = "") -> String {
        "![\(altText)](\(encode(relativePath)))"
    }

    /// Nur die Zeichen kodieren, die einen Markdown-Link zerbrechen würden.
    /// Umlaute bleiben lesbar (`_Anhänge`).
    static func encode(_ path: String) -> String {
        var result = ""
        for character in path {
            switch character {
            case " ": result += "%20"
            case "(": result += "%28"
            case ")": result += "%29"
            case "<": result += "%3C"
            case ">": result += "%3E"
            default: result.append(character)
            }
        }
        return result
    }

    public static func kind(of path: String) -> Kind? {
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp": .image
        case "pdf": .pdf
        default: nil
        }
    }

    static let pattern = try! NSRegularExpression(pattern: #"!\[([^\]\n]*)\]\((<[^>\n]+>|[^)\s]+)\)"#)
}
