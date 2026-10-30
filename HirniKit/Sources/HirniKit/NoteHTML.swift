import Foundation

/// Wandelt eine Notiz in eine HTML-Seite zum Drucken bzw. für den PDF-Export.
///
/// Bewusst nur das, was Hirni selbst kennt (siehe `MarkdownSyntax`):
/// Überschriften, Absätze, Listen, Checklisten, Zitate, Codeblöcke, Tabellen,
/// Bilder, eingebettete Datenbanken, fett/kursiv/durchgestrichen, Links, Tags.
public enum NoteHTML {
    /// Ein Bild für die Seite: Daten und Medientyp (`image/jpeg` …).
    public struct Image: Sendable {
        public let data: Data
        public let mimeType: String

        public init(data: Data, mimeType: String) {
            self.data = data
            self.mimeType = mimeType
        }
    }

    /// - Parameters:
    ///   - image: Pfad aus `![](…)` → Bild, `nil` wenn nicht vorhanden.
    ///   - database: `hirni-db`-Block → fertiges HTML (Tabelle), `nil` = Hinweis.
    public static func page(
        title: String,
        markdown: String,
        image: (String) -> Image? = { _ in nil },
        database: (DatabaseEmbed) -> String? = { _ in nil }
    ) -> String {
        let body = TemplateFiller.removingHints(Frontmatter.split(markdown).body)
        // Beginnt die Notiz schon mit dem Titel als Überschrift, nicht doppelt zeigen.
        let firstLine = body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let startsWithTitle = headingLevel(firstLine) != nil
            && firstLine.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) == title
        let heading = startsWithTitle ? "" : "<h1 class=\"title\">\(escape(title))</h1>"
        return """
        <!doctype html>
        <html lang="de"><head><meta charset="utf-8"><title>\(escape(title))</title>
        <style>\(css)</style></head>
        <body>\(heading)
        \(blocks(body, image: image, database: database))
        </body></html>
        """
    }

    static let css = """
    @page { margin: 18mm 16mm; }
    body { font: 11pt -apple-system, "Helvetica Neue", sans-serif; color: #1d1d1f; line-height: 1.45; }
    h1.title { font-size: 22pt; margin: 0 0 12pt; }
    h1 { font-size: 18pt; } h2 { font-size: 15pt; } h3 { font-size: 13pt; } h4, h5, h6 { font-size: 11pt; }
    h1, h2, h3, h4, h5, h6 { margin: 14pt 0 6pt; page-break-after: avoid; }
    p { margin: 0 0 8pt; }
    ul { margin: 0 0 8pt; padding-left: 18pt; }
    ul.tasks { list-style: none; padding-left: 4pt; }
    li.done .text { text-decoration: line-through; color: #8e8e93; }
    .box { display: inline-block; width: 14pt; }
    blockquote { margin: 0 0 8pt; padding-left: 10pt; border-left: 3px solid #d1d1d6; color: #636366; font-style: italic; }
    pre { background: #f2f2f7; padding: 8pt; border-radius: 4pt; white-space: pre-wrap; font: 9.5pt Menlo, monospace; }
    code { font: 9.5pt Menlo, monospace; background: #f2f2f7; padding: 0 2pt; }
    table { border-collapse: collapse; margin: 0 0 10pt; font-size: 9.5pt; page-break-inside: auto; }
    th, td { border: 1px solid #d1d1d6; padding: 3pt 6pt; text-align: left; vertical-align: top; }
    th { background: #f2f2f7; }
    td.number { text-align: right; }
    tfoot td { font-weight: 600; background: #f9f9fb; }
    tr { page-break-inside: avoid; }
    img { max-width: 100%; max-height: 120mm; border-radius: 4pt; margin: 2pt 0 8pt; }
    .tag { color: #007aff; }
    .date, .hint { color: #8e8e93; font-size: 8.5pt; }
    .db-title { font-weight: 600; margin: 10pt 0 4pt; }
    a { color: #007aff; text-decoration: none; }
    """

    // MARK: - Blöcke

    static func blocks(_ text: String, image: (String) -> Image?, database: (DatabaseEmbed) -> String?) -> String {
        let lines = text.components(separatedBy: "\n")
        let embeds = DatabaseEmbed.blocks(in: text)
        let tables = MarkdownTable.tables(in: text)
        // Zeilennummern von Tabellen und Datenbank-Blöcken (über Zeichenpositionen).
        var lineStarts: [Int] = []
        var offset = 0
        for line in lines {
            lineStarts.append(offset)
            offset += (line as NSString).length + 1
        }
        func lineIndex(at location: Int) -> Int {
            (lineStarts.lastIndex { $0 <= location }) ?? 0
        }

        var html: [String] = []
        var paragraph: [String] = []
        var list: (tasks: Bool, items: [String])?

        func flush() {
            if !paragraph.isEmpty {
                html.append("<p>" + paragraph.joined(separator: "<br>") + "</p>")
                paragraph = []
            }
            if let current = list {
                html.append((current.tasks ? "<ul class=\"tasks\">" : "<ul>") + current.items.joined() + "</ul>")
                list = nil
            }
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let embed = embeds.first(where: { lineIndex(at: $0.range.location) == index }) {
                flush()
                html.append(database(embed) ?? "<p class=\"hint\">[Datenbank «\(escape(embed.database))» nicht gefunden]</p>")
                index = lineIndex(at: NSMaxRange(embed.closingLine) - 1) + 1
                continue
            }
            if trimmed.hasPrefix("```") {
                flush()
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(escape(lines[index]))
                    index += 1
                }
                html.append("<pre><code>" + code.joined(separator: "\n") + "</code></pre>")
                index += 1
                continue
            }
            if let table = tables.first(where: { lineIndex(at: $0.range.location) == index }) {
                flush()
                html.append(tableHTML(table.rows))
                index = lineIndex(at: NSMaxRange(table.range) - 1) + 1
                continue
            }
            if trimmed.isEmpty {
                flush()
                index += 1
                continue
            }
            if let heading = headingLevel(trimmed) {
                flush()
                let content = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                html.append("<h\(heading)>\(inline(content))</h\(heading)>")
                index += 1
                continue
            }
            if trimmed.hasPrefix(">") {
                flush()
                var quote: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(inline(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)))
                    index += 1
                }
                html.append("<blockquote>" + quote.joined(separator: "<br>") + "</blockquote>")
                continue
            }
            if let done = TaskLine.state(of: line) {
                if !paragraph.isEmpty || list?.tasks == false { flush() }
                let indent = line.prefix { $0 == " " || $0 == "\t" }.count
                let content = TaskLine.content(of: line)
                let doneDate = TaskLine.date(TaskLine.doneMark, in: line).map { " <span class=\"date\">✓ \(TaskLine.format($0))</span>" } ?? ""
                let item = "<li class=\"\(done ? "done" : "open")\" style=\"margin-left:\(indent * 6)pt\"><span class=\"box\">\(done ? "☑" : "☐")</span><span class=\"text\">\(inline(content))</span>\(doneDate)</li>"
                list = (true, (list?.items ?? []) + [item])
                index += 1
                continue
            }
            if let item = listItem(line) {
                if !paragraph.isEmpty || list?.tasks == true { flush() }
                list = (false, (list?.items ?? []) + ["<li style=\"margin-left:\(item.indent * 6)pt\">\(inline(item.content))</li>"])
                index += 1
                continue
            }
            if list != nil { flush() }
            // Bild auf eigener Zeile: als Bild, sonst normaler Text.
            let embedsInLine = AttachmentLinks.embeds(in: trimmed)
            if embedsInLine.count == 1, embedsInLine[0].range.length == (trimmed as NSString).length {
                flush()
                html.append(imageHTML(embedsInLine[0], image: image))
                index += 1
                continue
            }
            paragraph.append(inline(line))
            index += 1
        }
        flush()
        return html.joined(separator: "\n")
    }

    static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    static func listItem(_ line: String) -> (indent: Int, content: String)? {
        let ns = line as NSString
        guard let m = MarkdownSyntax.Patterns.list.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let indent = line.prefix { $0 == " " || $0 == "\t" }.count
        return (indent, ns.substring(from: NSMaxRange(m.range)))
    }

    static func tableHTML(_ rows: [[String]]) -> String {
        guard let header = rows.first else { return "" }
        let head = "<thead><tr>" + header.map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead>"
        let body = rows.dropFirst().map { row in
            "<tr>" + row.map { "<td>\(inline($0).replacingOccurrences(of: "\n", with: "<br>"))</td>" }.joined() + "</tr>"
        }.joined()
        return "<table>\(head)<tbody>\(body)</tbody></table>"
    }

    static func imageHTML(_ embed: EmbedLink, image: (String) -> Image?) -> String {
        let name = escape((embed.path as NSString).lastPathComponent)
        guard AttachmentLinks.kind(of: embed.path) == .image, let img = image(embed.path) else {
            return "<p class=\"hint\">[\(AttachmentLinks.kind(of: embed.path) == .pdf ? "PDF" : "Anhang"): \(name)]</p>"
        }
        return "<p><img src=\"data:\(img.mimeType);base64,\(img.data.base64EncodedString())\" alt=\"\(escape(embed.altText))\"></p>"
    }

    // MARK: - Inline

    /// Escaping und Inline-Formatierung einer Zeile.
    static func inline(_ text: String) -> String {
        var result = ""
        let ns = text as NSString
        // Bilder mitten im Text: als Hinweis (Bilder stehen sonst auf eigener Zeile).
        var last = 0
        for embed in AttachmentLinks.embeds(in: text) {
            result += formatted(ns.substring(with: NSRange(last..<embed.range.location)))
            result += "<span class=\"hint\">[\(escape((embed.path as NSString).lastPathComponent))]</span>"
            last = NSMaxRange(embed.range)
        }
        return result + formatted(ns.substring(from: last))
    }

    private static func formatted(_ raw: String) -> String {
        // Links zuerst herausnehmen, damit `_` und `*` in Adressen nichts formatieren.
        var placeholders: [String] = []
        func hold(_ html: String) -> String {
            placeholders.append(html)
            return "\u{E000}\(placeholders.count - 1)\u{E001}"
        }
        var text = raw
        text = replace(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#, in: text) { groups in
            hold("<a href=\"\(escape(groups[2]))\">\(escape(groups[1]))</a>")
        }
        text = replace(#"`([^`\n]+)`"#, in: text) { groups in hold("<code>\(escape(groups[1]))</code>") }
        text = replace(#"(?<![\w@/.])(?:https?://|www\.)[^\s<>\[\]]+[^\s<>\[\].,;:!?'")]"#, in: text) { groups in
            let url = groups[0].lowercased().hasPrefix("www.") ? "https://" + groups[0] : groups[0]
            return hold("<a href=\"\(escape(url))\">\(escape(groups[0]))</a>")
        }
        text = replace(#"[ \t]*(➕|✅)[ \t]*(\d{4}-\d{2}-\d{2})"#, in: text) { _ in "" }
        text = escape(text)
        text = replace(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#, in: text) { "<strong>\($0[2])</strong>" }
        text = replace(#"(?<![*_\w])([*_])(?=\S)(.+?)(?<=\S)\1(?![*_\w])"#, in: text) { "<em>\($0[2])</em>" }
        text = replace(#"~~(?=\S)(.+?)(?<=\S)~~"#, in: text) { "<del>\($0[1])</del>" }
        text = replace(#"(?<![\w#/&])#([\p{L}\p{N}_/-]*[\p{L}_/-][\p{L}\p{N}_/-]*)"#, in: text) { "<span class=\"tag\">#\($0[1])</span>" }
        for (index, html) in placeholders.enumerated() {
            text = text.replacingOccurrences(of: "\u{E000}\(index)\u{E001}", with: html)
        }
        return text
    }

    private static func replace(_ pattern: String, in text: String, with transform: ([String]) -> String) -> String {
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(last..<m.range.location))
            let groups = (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
            result += transform(groups)
            last = NSMaxRange(m.range)
        }
        return result + ns.substring(from: last)
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Datenbanken

    /// Eine Datenbank-Ansicht als Tabelle: sichtbare Felder, Zeilen nach
    /// Filter und Sortierung der Ansicht, Gruppen als Zwischenzeilen,
    /// Berechnungen in der Fusszeile. Kalender und Diagramm erscheinen
    /// ebenfalls als Tabelle ihrer Einträge.
    public static func databaseTable(_ database: Database, view viewName: String?, title: String) -> String {
        let view = database.views.first { $0.name == viewName } ?? database.views.first
        let result = DatabaseQuery.run(view, on: database)
        let hidden = Set(view?.hiddenFields ?? [])
        let fields = database.fields.filter { !hidden.contains($0.name) }
        let caption = escape(title) + (view.map { " · " + escape($0.name) } ?? "")

        var rows = ""
        for group in result.groups {
            if let groupTitle = group.title {
                rows += "<tr><td colspan=\"\(fields.count)\"><strong>\(escape(groupTitle))</strong> <span class=\"hint\">\(group.rows.count)</span></td></tr>"
            }
            for row in group.rows {
                rows += "<tr>" + fields.map { field in
                    let value = field.type == .checkbox ? (CellValue.bool(row[field.name]) ? "☑" : "☐") : CellValue.display(row[field.name], for: field)
                    return "<td\(field.type == .number ? " class=\"number\"" : "")>\(escape(value))</td>"
                }.joined() + "</tr>"
            }
        }
        var footer = ""
        if let aggregates = view?.aggregates, !aggregates.isEmpty {
            footer = "<tfoot><tr>" + fields.map { field in
                guard let aggregate = aggregates[field.name] else { return "<td></td>" }
                return "<td\(field.type == .number ? " class=\"number\"" : "")>\(escape(aggregate.label)) \(escape(DatabaseQuery.display(aggregate, field: field, rows: result.rows)))</td>"
            }.joined() + "</tr></tfoot>"
        }
        let head = "<thead><tr>" + fields.map { "<th>\(escape($0.name))</th>" }.joined() + "</tr></thead>"
        return "<div class=\"db-title\">\(caption)</div><table>\(head)<tbody>\(rows)</tbody>\(footer)</table>"
    }
}

extension Vault {
    /// HTML-Seite einer Notiz mit Bildern und eingebetteten Datenbanken.
    public func html(ofNote url: URL) throws -> String {
        let text = try readNote(at: url)
        return NoteHTML.page(
            title: Self.title(of: url),
            markdown: text,
            image: { path in
                guard let file = self.resolveAttachment(path, for: url),
                      let data = try? Coordinated.read(file, { try Data(contentsOf: $0) }) else { return nil }
                let ext = file.pathExtension.lowercased()
                let mime = switch ext {
                case "png": "image/png"
                case "gif": "image/gif"
                case "heic", "heif": "image/heic"
                case "webp": "image/webp"
                default: "image/jpeg"
                }
                return NoteHTML.Image(data: data, mimeType: mime)
            },
            database: { embed in
                guard let dbURL = self.resolveDatabase(embed.database, from: url),
                      let database = try? self.readDatabase(at: dbURL) else { return nil }
                return NoteHTML.databaseTable(database, view: embed.view, title: Self.title(of: dbURL))
            }
        )
    }
}
