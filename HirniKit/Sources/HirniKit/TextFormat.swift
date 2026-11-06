import Foundation

/// Textfarben. Der Rohwert ist der CSS-Name, so steht er in der Datei:
/// `<span style="color:red">Text</span>`.
public enum TextColor: String, CaseIterable, Sendable {
    case red, orange, green, blue, purple, gray

    public var label: String {
        switch self {
        case .red: "Rot"
        case .orange: "Orange"
        case .green: "Grün"
        case .blue: "Blau"
        case .purple: "Violett"
        case .gray: "Grau"
        }
    }
}

/// Formate, die Markdown selbst nicht kennt, als HTML-Tags in der Zeile.
/// So bleibt die Datei gewöhnliches Markdown; Obsidian zeigt sie ebenfalls an.
/// Im Editor sind die Tags ausgeblendet. Die letzte Gruppe ist jeweils der Text.
struct TextFormat: Sendable {
    let pattern: NSRegularExpression
    let kind: @Sendable (NSString, NSTextCheckingResult) -> MarkdownSpan.Kind

    static let underline = TextFormat(pattern: try! NSRegularExpression(pattern: "<u>(.+?)</u>")) { _, _ in .underline }
    static let highlight = TextFormat(pattern: try! NSRegularExpression(pattern: "<mark>(.+?)</mark>")) { _, _ in .highlight }
    static let color = TextFormat(pattern: try! NSRegularExpression(pattern: #"<span style="color:([a-z]+)">(.+?)</span>"#)) { text, match in
        TextColor(rawValue: text.substring(with: match.range(at: 1))).map(MarkdownSpan.Kind.textColor) ?? .syntax
    }

    static let all = [underline, highlight, color]
}
