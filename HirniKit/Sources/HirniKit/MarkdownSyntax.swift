import Foundation

/// Ein erkannter Markdown-Bereich im Text, für die Hervorhebung im Editor.
/// Bereiche sind `NSRange` (UTF-16), so wie Text-Views sie verwenden.
public struct MarkdownSpan: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Die ganze Überschriftenzeile.
        case heading(level: Int)
        /// Markdown-Zeichen selbst (`#`, `**`, `>` …) – werden grau dargestellt.
        case syntax
        case bold
        case italic
        case strikethrough
        case inlineCode
        /// Eine Zeile in einem ```-Codeblock (inklusive der ```-Zeilen).
        case codeBlock
        case quote
        case listMarker
        /// `[ ]` bzw. `[x]` einer Checkliste.
        case checkbox(checked: Bool)
        /// Text eines erledigten Checklisten-Punkts.
        case doneItem
        case link
        case tag(String)
    }

    public let kind: Kind
    public let range: NSRange

    public init(_ kind: Kind, _ range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

/// Erkennt die Markdown-Elemente, die hirni hervorhebt. Bewusst einfach und
/// zeilenbasiert: Es geht um Darstellung beim Schreiben, nicht um eine
/// vollständige Markdown-Umsetzung.
public enum MarkdownSyntax {
    public static func spans(in text: String) -> [MarkdownSpan] {
        let ns = text as NSString
        var spans: [MarkdownSpan] = []
        var inFence = false

        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]
        ) { _, line, _, _ in
            if Patterns.fence.firstMatch(in: text, range: line) != nil {
                spans.append(MarkdownSpan(.codeBlock, line))
                spans.append(MarkdownSpan(.syntax, line))
                inFence.toggle()
                return
            }
            if inFence {
                spans.append(MarkdownSpan(.codeBlock, line))
                return
            }
            spans += lineSpans(in: text, line: line)
        }
        return spans
    }

    /// Alle `#tags` im Text (ohne `#`), ohne Doppelte (Gross/klein egal).
    public static func tags(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for span in spans(in: text) {
            if case .tag(let name) = span.kind, seen.insert(name.lowercased()).inserted {
                result.append(name)
            }
        }
        return result
    }

    // MARK: - Zeilen

    private static func lineSpans(in text: String, line: NSRange) -> [MarkdownSpan] {
        var spans: [MarkdownSpan] = []
        var contentStart = line.location

        if let m = Patterns.heading.firstMatch(in: text, range: line) {
            let level = m.range(at: 1).length
            spans.append(MarkdownSpan(.heading(level: level), line))
            spans.append(MarkdownSpan(.syntax, m.range))
            contentStart = NSMaxRange(m.range)
        } else if let m = Patterns.quote.firstMatch(in: text, range: line) {
            spans.append(MarkdownSpan(.quote, line))
            spans.append(MarkdownSpan(.syntax, m.range(at: 1)))
            contentStart = NSMaxRange(m.range)
        } else if let m = Patterns.checkbox.firstMatch(in: text, range: line) {
            let box = m.range(at: 3)
            let checked = (text as NSString).substring(with: box).lowercased() == "[x]"
            spans.append(MarkdownSpan(.listMarker, m.range(at: 2)))
            spans.append(MarkdownSpan(.checkbox(checked: checked), box))
            contentStart = NSMaxRange(m.range)
            if checked, NSMaxRange(line) > contentStart {
                spans.append(MarkdownSpan(.doneItem, NSRange(contentStart..<NSMaxRange(line))))
            }
        } else if let m = Patterns.list.firstMatch(in: text, range: line) {
            spans.append(MarkdownSpan(.listMarker, m.range(at: 2)))
            contentStart = NSMaxRange(m.range)
        }

        let content = NSRange(contentStart..<NSMaxRange(line))
        if content.length > 0 {
            spans += inlineSpans(in: text, range: content)
        }
        return spans
    }

    private static func inlineSpans(in text: String, range: NSRange) -> [MarkdownSpan] {
        var spans: [MarkdownSpan] = []

        // Inline-Code zuerst: Was darin steht, ist kein Markdown.
        var protected: [NSRange] = []
        for m in Patterns.inlineCode.matches(in: text, range: range) {
            protected.append(m.range)
            spans.append(MarkdownSpan(.inlineCode, m.range))
            spans.append(MarkdownSpan(.syntax, NSRange(location: m.range.location, length: 1)))
            spans.append(MarkdownSpan(.syntax, NSRange(location: NSMaxRange(m.range) - 1, length: 1)))
        }
        func isFree(_ r: NSRange) -> Bool {
            !protected.contains { NSIntersectionRange($0, r).length > 0 }
        }

        var boldMarkers: [NSRange] = []
        for m in Patterns.bold.matches(in: text, range: range) where isFree(m.range) {
            let open = NSRange(location: m.range.location, length: 2)
            let close = NSRange(location: NSMaxRange(m.range) - 2, length: 2)
            boldMarkers += [open, close]
            spans.append(MarkdownSpan(.bold, m.range(at: 2)))
            spans += [MarkdownSpan(.syntax, open), MarkdownSpan(.syntax, close)]
        }

        for m in Patterns.italic.matches(in: text, range: range) where isFree(m.range) {
            // `**fett**` darf nicht zusätzlich als kursiv gelten.
            if boldMarkers.contains(where: { NSLocationInRange(m.range.location, $0) }) { continue }
            spans.append(MarkdownSpan(.italic, m.range(at: 2)))
            spans.append(MarkdownSpan(.syntax, NSRange(location: m.range.location, length: 1)))
            spans.append(MarkdownSpan(.syntax, NSRange(location: NSMaxRange(m.range) - 1, length: 1)))
        }

        for m in Patterns.strikethrough.matches(in: text, range: range) where isFree(m.range) {
            spans.append(MarkdownSpan(.strikethrough, m.range(at: 1)))
            spans.append(MarkdownSpan(.syntax, NSRange(location: m.range.location, length: 2)))
            spans.append(MarkdownSpan(.syntax, NSRange(location: NSMaxRange(m.range) - 2, length: 2)))
        }

        for m in Patterns.link.matches(in: text, range: range) where isFree(m.range) {
            let label = m.range(at: 1)
            spans.append(MarkdownSpan(.link, label))
            spans.append(MarkdownSpan(.syntax, NSRange(location: m.range.location, length: 1)))
            spans.append(MarkdownSpan(.syntax, NSRange(NSMaxRange(label)..<NSMaxRange(m.range))))
        }

        for m in Patterns.tag.matches(in: text, range: range) where isFree(m.range) {
            let name = (text as NSString).substring(with: m.range(at: 1))
            spans.append(MarkdownSpan(.tag(name), m.range))
        }
        return spans
    }

    // MARK: - Muster

    enum Patterns {
        static let fence = regex(#"^\s*```"#)
        static let heading = regex(#"^(#{1,6})[ \t]+"#)
        static let quote = regex(#"^\s*(>)[ \t]?"#)
        static let checkbox = regex(#"^(\s*)([-*+])[ \t]+(\[[ xX]\])(?=[ \t]|$)[ \t]?"#)
        static let list = regex(#"^(\s*)([-*+]|\d+[.)])[ \t]+"#)
        static let inlineCode = regex(#"`[^`\n]+`"#)
        static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
        static let italic = regex(#"(?<![*_\w])([*_])(?=\S)(.+?)(?<=\S)\1(?![*_\w])"#)
        static let strikethrough = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
        static let link = regex(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
        /// Wie Obsidian: Buchstaben, Ziffern, `_`, `-`, `/`, aber nicht nur Ziffern.
        static let tag = regex(#"(?<![\w#/&])#([\p{L}\p{N}_/-]*[\p{L}_/-][\p{L}\p{N}_/-]*)"#)

        private static func regex(_ pattern: String) -> NSRegularExpression {
            // Die Muster sind fest im Code: Ein Fehler hier ist ein Programmierfehler.
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
    }
}
