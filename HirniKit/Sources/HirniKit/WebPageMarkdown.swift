import Foundation

/// Übernimmt den Inhalt einer Webseite als Markdown. Ein Skript im Browser
/// (`extractionScript`) liefert den Hauptinhalt der Seite als vereinfachten
/// Baum; daraus entsteht hier der Text: Überschriften, Absätze, Listen,
/// Zitate, Code, Tabellen, fett und kursiv. Links bleiben nur, wo sie für
/// sich stehen (Listenpunkt, der nur aus einem Link besteht); im Fliesstext
/// bleibt das Wort, sonst wäre der Text vor lauter Adressen kaum lesbar.
/// Bilder, Menüs, Fusszeilen, Formulare und Skripte fallen weg.
public enum WebPageMarkdown {
    /// Ein Element (`g` = Tag) oder ein Textstück (`t`).
    public struct Node: Codable, Equatable, Sendable {
        public var g: String?
        public var t: String?
        /// Ziel eines Links (absolut).
        public var h: String?
        public var c: [Node]?

        public init(_ tag: String, href: String? = nil, _ children: [Node] = []) {
            g = tag
            h = href
            c = children
        }

        public init(text: String) {
            t = text
        }

        var children: [Node] { c ?? [] }
        var tag: String { g ?? "" }
    }

    public struct Page: Codable, Sendable {
        public var title: String
        public var root: Node
    }

    /// Liest die Antwort von `extractionScript`.
    public static func page(fromJSON json: String) throws -> Page {
        try JSONDecoder().decode(Page.self, from: Data(json.utf8))
    }

    public static func markdown(from root: Node) -> String {
        let text = blocks(root, depth: 0).joined(separator: "\n\n")
        // Höchstens eine Leerzeile am Stück.
        return text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Blöcke

    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "main", "header", "h1", "h2", "h3", "h4", "h5", "h6",
        "ul", "ol", "li", "blockquote", "pre", "table", "hr", "figure", "figcaption", "dl", "dt", "dd",
        "details", "summary", "address", "body",
    ]

    private static func isBlock(_ node: Node) -> Bool {
        blockTags.contains(node.tag) || node.children.contains(where: isBlock)
    }

    private static func blocks(_ node: Node, depth: Int) -> [String] {
        switch node.tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let text = inline(node.children).replacingOccurrences(of: "\n", with: " ")
            guard !text.isEmpty else { return [] }
            return [String(repeating: "#", count: Int(node.tag.dropFirst()) ?? 1) + " " + text]
        case "ul", "ol":
            let list = listLines(node, depth: depth)
            return list.isEmpty ? [] : [list.joined(separator: "\n")]
        case "blockquote":
            let inner = node.children.flatMap { blocks($0, depth: depth) }.joined(separator: "\n\n")
            guard !inner.isEmpty else { return [] }
            return [inner.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")]
        case "pre":
            let code = rawText(node).trimmingCharacters(in: .newlines)
            return code.isEmpty ? [] : ["```\n" + code + "\n```"]
        case "table":
            return table(node).map { [$0] } ?? []
        case "hr":
            return ["---"]
        case "img", "figcaption":
            // Ohne Bilder ergeben Bildunterschriften keinen Sinn.
            return []
        case "br" where node.t == nil:
            return []
        default:
            if node.t != nil || !isBlock(node) {
                let text = inline([node])
                return text.isEmpty ? [] : [text]
            }
            // Behälter: Text zwischen Blöcken wird zu eigenen Absätzen.
            var result: [String] = []
            var pending: [Node] = []
            func flush() {
                let text = inline(pending)
                if !text.isEmpty { result.append(text) }
                pending = []
            }
            for child in node.children {
                if isBlock(child) {
                    flush()
                    result += blocks(child, depth: depth)
                } else {
                    pending.append(child)
                }
            }
            flush()
            return result
        }
    }

    private static func listLines(_ list: Node, depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        var lines: [String] = []
        var number = 1
        for item in list.children where item.tag == "li" {
            let nested = item.children.filter { $0.tag == "ul" || $0.tag == "ol" }
            let content = item.children.filter { $0.tag != "ul" && $0.tag != "ol" }
            let meaningful = content.filter { $0.t == nil || !$0.t!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let text = (meaningful.count == 1 && meaningful[0].tag == "a"
                ? inline(meaningful, links: true)
                : content.flatMap { blocks($0, depth: depth) }.joined(separator: " "))
                .replacingOccurrences(of: "\n", with: " ")
            let marker = list.tag == "ol" ? "\(number). " : "- "
            if !text.isEmpty {
                lines.append(indent + marker + text)
                number += 1
            }
            for sub in nested { lines += listLines(sub, depth: depth + 1) }
        }
        return lines
    }

    private static func table(_ node: Node) -> String? {
        func rows(_ node: Node) -> [Node] {
            node.tag == "tr" ? [node] : node.children.flatMap(rows)
        }
        let cells = rows(node).map { row in
            row.children.filter { $0.tag == "td" || $0.tag == "th" }.map {
                inline($0.children).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "\\|")
            }
        }.filter { !$0.isEmpty }
        guard let width = cells.map(\.count).max(), width > 0 else { return nil }
        let padded = cells.map { $0 + Array(repeating: "", count: width - $0.count) }
        let line = { (row: [String]) in "| " + row.joined(separator: " | ") + " |" }
        return ([line(padded[0]), line(Array(repeating: "---", count: width))] + padded.dropFirst().map(line))
            .joined(separator: "\n")
    }

    // MARK: - Inline

    private static func inline(_ nodes: [Node], links: Bool = false) -> String {
        let text = nodes.map { inlineText($0, links: links) }.joined()
        return text.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func inlineText(_ node: Node, links: Bool) -> String {
        if let text = node.t {
            return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }
        let inner = node.children.map { inlineText($0, links: links) }.joined()
        switch node.tag {
        case "br":
            return "\n"
        case "a":
            let label = inner.trimmingCharacters(in: .whitespaces)
            // Fussnoten-Verweise wie «[1]» ergeben ohne die Fussnoten keinen Sinn.
            if label.range(of: #"^\[\d+\]$"#, options: .regularExpression) != nil { return "" }
            guard links, let href = node.h, href.hasPrefix("http"), !label.isEmpty else { return inner }
            return label == href ? href : wrap(inner, "[", "](\(href))")
        case "strong", "b":
            return wrap(inner, "**", "**")
        case "em", "i":
            return wrap(inner, "*", "*")
        case "code":
            return wrap(inner, "`", "`")
        case "img":
            return ""
        default:
            // Blöcke in Absätzen (z. B. `div` in `li`) trennt ein Leerzeichen.
            return blockTags.contains(node.tag) ? " " + inner + " " : inner
        }
    }

    /// Setzt Zeichen innen um den Text, Leerzeichen bleiben aussen.
    private static func wrap(_ text: String, _ open: String, _ close: String) -> String {
        let core = text.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return text }
        let leading = text.hasPrefix(" ") ? " " : ""
        let trailing = text.hasSuffix(" ") ? " " : ""
        return leading + open + core + close + trailing
    }

    private static func rawText(_ node: Node) -> String {
        if let text = node.t { return text }
        if node.tag == "br" { return "\n" }
        return node.children.map(rawText).joined()
    }

    // MARK: - Skript

    /// Läuft in der Webseite und liefert `Page` als JSON. Hauptinhalt ist das
    /// `article`/`main` mit dem meisten Text, sonst die ganze Seite.
    public static let extractionScript = #"""
    (() => {
      const skip = new Set(["SCRIPT","STYLE","NOSCRIPT","SVG","NAV","FOOTER","ASIDE","FORM","BUTTON","IFRAME","TEMPLATE","CANVAS","VIDEO","AUDIO","SELECT","INPUT","TEXTAREA","DIALOG"]);
      const candidates = [...document.querySelectorAll("article, main, [role=main]")];
      let root = candidates.sort((a, b) => b.innerText.length - a.innerText.length)[0];
      if (!root || root.innerText.length < 300) root = document.body;
      const isBody = root === document.body;
      const skipRoles = new Set(["navigation","menu","menubar","tablist","toolbar","banner","contentinfo","search","dialog"]);
      const skipNames = /(^|[-_ ])(nav|navbar|menu|toolbar|breadcrumbs?|share|social|cookie|tabs?|tab-container)([-_ ]|$)/i;
      const hidden = el => {
        if (el.getAttribute("aria-hidden") === "true" || el.hidden) return true;
        if (skipRoles.has(el.getAttribute("role"))) return true;
        if (skipNames.test((typeof el.className === "string" ? el.className : "") + " " + el.id)) return true;
        const style = getComputedStyle(el);
        return style.display === "none" || style.visibility === "hidden";
      };
      const walk = node => {
        if (node.nodeType === Node.TEXT_NODE) return node.nodeValue.trim() === "" && !/ /.test(node.nodeValue) ? null : { t: node.nodeValue };
        if (node.nodeType !== Node.ELEMENT_NODE) return null;
        if (skip.has(node.tagName) || (isBody && node.tagName === "HEADER") || hidden(node)) return null;
        const result = { g: node.tagName.toLowerCase(), c: [] };
        if (node.tagName === "A" && node.href) result.h = node.href;
        for (const child of node.childNodes) {
          const converted = walk(child);
          if (converted) result.c.push(converted);
        }
        return result;
      };
      return JSON.stringify({ title: document.title || "", root: walk(root) || { g: "div", c: [] } });
    })()
    """#
}
