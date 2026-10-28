import Foundation

/// Eine Textänderung: `range` wird durch `replacement` ersetzt, danach gilt
/// `selection` (alles in UTF-16, bezogen auf den Text *nach* der Änderung).
public struct TextEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// Wendet die Änderung auf `text` an (für Tests und Vorschau).
    public func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

/// Die Befehle der Formatierungsleiste und Tastenkürzel. Reine Textfunktionen,
/// damit sie ohne Oberfläche getestet werden können.
public enum MarkdownEditing {
    // MARK: - Fett, kursiv

    /// `**` um die Auswahl setzen oder wieder entfernen. Ohne Auswahl werden
    /// zwei Marker eingefügt und der Cursor dazwischen gesetzt.
    public static func toggleWrap(_ marker: String, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let m = (marker as NSString).length

        if selection.length == 0 {
            return TextEdit(
                range: selection, replacement: marker + marker,
                selection: NSRange(location: selection.location + m, length: 0)
            )
        }

        let selected = ns.substring(with: selection)
        // Auswahl enthält die Marker selbst: «**fett**» → «fett»
        if selection.length >= 2 * m, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = (selected as NSString).substring(with: NSRange(location: m, length: selection.length - 2 * m))
            return TextEdit(
                range: selection, replacement: inner,
                selection: NSRange(location: selection.location, length: (inner as NSString).length)
            )
        }
        // Marker stehen direkt um die Auswahl: **|fett|**
        if selection.location >= m, NSMaxRange(selection) + m <= ns.length,
           ns.substring(with: NSRange(location: selection.location - m, length: m)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(selection), length: m)) == marker {
            return TextEdit(
                range: NSRange(location: selection.location - m, length: selection.length + 2 * m),
                replacement: selected,
                selection: NSRange(location: selection.location - m, length: selection.length)
            )
        }
        return TextEdit(
            range: selection, replacement: marker + selected + marker,
            selection: NSRange(location: selection.location + m, length: selection.length)
        )
    }

    // MARK: - Zeilen

    public enum LineStyle: Sendable {
        case bullet
        case checkbox
    }

    /// Macht die ausgewählten Zeilen zur Liste bzw. Checkliste – oder wieder
    /// zu normalem Text, wenn sie es schon alle sind.
    public static func toggleLineStyle(_ style: LineStyle, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let lines = lineBlock(in: ns, selection: selection)
        let parsed = lines.text.components(separatedBy: "\n").map(LinePrefix.init)
        let nonEmpty = parsed.filter { !$0.rest.isEmpty || $0.marker != nil }
        let allHaveStyle = !nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.style == style }
        // Leerzeilen zwischen markierten Zeilen bleiben leer. Ist aber gar nichts
        // ausser Leerzeilen da (Cursor in einer leeren Zeile), beginnt dort die Liste.
        let keepEmptyLines = !nonEmpty.isEmpty

        let newLines = parsed.map { line -> String in
            if keepEmptyLines && line.rest.isEmpty && line.marker == nil { return line.original }
            if allHaveStyle { return line.indent + line.rest }
            switch style {
            case .bullet: return line.indent + "- " + line.rest
            case .checkbox: return line.indent + "- [ ] " + line.rest
            }
        }
        let replacement = newLines.joined(separator: "\n")
        return lineEdit(lines: lines, replacement: replacement, firstLineDelta: delta(parsed[0], newLines[0]), selection: selection)
    }

    /// Überschrift der aktuellen Zeile: keine → # → ## → ### → keine.
    public static func cycleHeading(in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        var line = ns.substring(with: lineRange)
        let newline = line.hasSuffix("\n") ? "\n" : ""
        if !newline.isEmpty { line.removeLast() }

        let hashes = line.prefix { $0 == "#" }.count
        let hasHeading = hashes > 0 && line.dropFirst(hashes).hasPrefix(" ")
        let level = hasHeading ? hashes : 0
        let rest = hasHeading ? String(line.dropFirst(hashes + 1)) : line
        let next = level == 0 ? 1 : (level < 3 ? level + 1 : 0)
        let newLine = (next == 0 ? "" : String(repeating: "#", count: next) + " ") + rest

        let shift = (newLine as NSString).length - (line as NSString).length
        let caret = max(lineRange.location, selection.location + shift)
        return TextEdit(
            range: NSRange(location: lineRange.location, length: (line as NSString).length),
            replacement: newLine,
            selection: NSRange(location: caret, length: selection.length)
        )
    }

    // MARK: - Checklisten

    /// Hakt die Checkbox ab bzw. wieder an, wenn `index` auf `[ ]`/`[x]` liegt.
    /// Die Auswahl bleibt, wo sie war.
    /// Beim Abhaken kommt `✅ Datum` ans Zeilenende, beim Öffnen fällt es weg
    /// (für die Pendenzenliste).
    public static func toggleCheckbox(at index: Int, in text: String, keeping selection: NSRange, now: Date = .now) -> TextEdit? {
        let ns = text as NSString
        guard index >= 0, index <= ns.length else { return nil }
        let lineRange = ns.lineRange(for: NSRange(location: min(index, max(ns.length - 1, 0)), length: 0))
        guard let m = MarkdownSyntax.Patterns.checkbox.firstMatch(in: text, range: lineRange) else { return nil }
        let box = m.range(at: 3)
        // Ein Tipp knapp daneben zählt auch.
        guard index >= box.location, index <= NSMaxRange(box) else { return nil }
        let checked = ns.substring(with: box).lowercased() == "[x]"
        let hasNewline = ns.substring(with: lineRange).hasSuffix("\n")
        let line = NSRange(location: lineRange.location, length: lineRange.length - (hasNewline ? 1 : 0))
        let replacement = TaskLine.setDone(!checked, line: ns.substring(with: line), now: now)
        let delta = (replacement as NSString).length - line.length
        let caret = selection.location > NSMaxRange(line) ? selection.location + delta : min(selection.location, line.location + (replacement as NSString).length)
        return TextEdit(range: line, replacement: replacement, selection: NSRange(location: caret, length: 0))
    }

    /// Nach Return in einer Listen- oder Checklistenzeile: neue Zeile mit
    /// demselben Marker. Ist die Zeile leer (nur Marker), wird der Marker
    /// entfernt und die Liste beendet – wie in Apple Notizen.
    public static func continueList(in text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        let lineStart = lineRange.location
        let beforeCaret = ns.substring(with: NSRange(lineStart..<selection.location))
        let prefix = LinePrefix(beforeCaret)
        guard prefix.marker != nil else { return nil }

        let lineEnd = NSMaxRange(lineRange) - (ns.substring(with: lineRange).hasSuffix("\n") ? 1 : 0)
        let wholeLine = LinePrefix(ns.substring(with: NSRange(lineStart..<lineEnd)))
        if wholeLine.rest.isEmpty {
            return TextEdit(
                range: NSRange(lineStart..<lineEnd), replacement: "",
                selection: NSRange(location: lineStart, length: 0)
            )
        }
        let marker = prefix.indent + (prefix.style == .checkbox ? "- [ ] " : prefix.markerText)
        let insertion = "\n" + marker
        return TextEdit(
            range: selection, replacement: insertion,
            selection: NSRange(location: selection.location + (insertion as NSString).length, length: 0)
        )
    }

    // MARK: - Anhänge

    /// Fügt einen Block (z. B. `![](_Anhänge/foto.jpg)`) auf einer eigenen
    /// Zeile ein. Der Cursor steht danach am Anfang der nächsten Zeile.
    public static func insertBlock(_ block: String, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let start = selection.location
        let atLineStart = start == 0 || ns.character(at: start - 1) == 0x0A
        let insertion = (atLineStart ? "" : "\n") + block + "\n"
        let caret = start + (insertion as NSString).length
        return TextEdit(
            range: selection,
            replacement: insertion,
            selection: NSRange(location: caret, length: 0)
        )
    }

    // MARK: - Tags

    /// Steht der Cursor direkt hinter `#abc`, liefert dies den Bereich `#abc`
    /// und den bisher getippten Teil `abc` (für Vorschläge).
    public static func tagQuery(in text: String, caret: Int) -> (range: NSRange, query: String)? {
        let ns = text as NSString
        guard caret > 0, caret <= ns.length else { return nil }
        var start = caret
        while start > 0, let scalar = Unicode.Scalar(ns.character(at: start - 1)), isTagCharacter(scalar) {
            start -= 1
        }
        guard start > 0, ns.character(at: start - 1) == 0x23 /* # */ else { return nil }
        let hash = start - 1
        if hash > 0, let before = Unicode.Scalar(ns.character(at: hash - 1)),
           !CharacterSet.whitespacesAndNewlines.contains(before) {
            return nil
        }
        let query = ns.substring(with: NSRange(start..<caret))
        return (NSRange(hash..<caret), query)
    }

    /// Ersetzt die angefangene Eingabe `#ab` durch `#abc ` (mit Leerzeichen,
    /// ausser es folgt schon eines). Ein Zeilenumbruch zählt nicht als
    /// Leerzeichen, sonst spränge der Cursor in die nächste Zeile.
    public static func completeTag(_ tag: String, replacing range: NSRange, in text: String) -> TextEdit {
        let ns = text as NSString
        let followedBySpace = NSMaxRange(range) < ns.length
            && Unicode.Scalar(ns.character(at: NSMaxRange(range))).map(CharacterSet.whitespaces.contains) == true
        let replacement = "#" + tag + (followedBySpace ? "" : " ")
        return TextEdit(
            range: range, replacement: replacement,
            selection: NSRange(location: range.location + (replacement as NSString).length + (followedBySpace ? 1 : 0), length: 0)
        )
    }

    private static func isTagCharacter(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
            || scalar == "_" || scalar == "-" || scalar == "/"
    }

    // MARK: - Hilfen

    private struct LineBlock {
        let range: NSRange // ohne abschliessenden Zeilenumbruch
        let text: String
    }

    private static func lineBlock(in ns: NSString, selection: NSRange) -> LineBlock {
        var range = ns.lineRange(for: selection)
        if range.length > 0, ns.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1)) == "\n" {
            range.length -= 1
        }
        return LineBlock(range: range, text: ns.substring(with: range))
    }

    private static func lineEdit(lines: LineBlock, replacement: String, firstLineDelta: Int, selection: NSRange) -> TextEdit {
        let newSelection: NSRange
        if selection.length == 0 {
            newSelection = NSRange(location: max(lines.range.location, selection.location + firstLineDelta), length: 0)
        } else {
            newSelection = NSRange(location: lines.range.location, length: (replacement as NSString).length)
        }
        return TextEdit(range: lines.range, replacement: replacement, selection: newSelection)
    }

    private static func delta(_ old: LinePrefix, _ new: String) -> Int {
        (new as NSString).length - (old.original as NSString).length
    }

    /// Zerlegt eine Zeile in Einrückung, Listen-Marker und Rest.
    private struct LinePrefix {
        let original: String
        let indent: String
        let marker: String?
        let rest: String

        var markerText: String { marker ?? "" }

        var style: LineStyle? {
            guard let marker else { return nil }
            return marker.contains("[") ? .checkbox : .bullet
        }

        init(_ line: String) {
            original = line
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            if let m = MarkdownSyntax.Patterns.checkbox.firstMatch(in: line, range: full) {
                indent = ns.substring(with: m.range(at: 1))
                marker = ns.substring(with: NSRange(location: m.range(at: 2).location, length: NSMaxRange(m.range) - m.range(at: 2).location))
                rest = ns.substring(from: NSMaxRange(m.range))
            } else if let m = MarkdownSyntax.Patterns.list.firstMatch(in: line, range: full) {
                indent = ns.substring(with: m.range(at: 1))
                marker = ns.substring(with: NSRange(location: m.range(at: 2).location, length: NSMaxRange(m.range) - m.range(at: 2).location))
                rest = ns.substring(from: NSMaxRange(m.range))
            } else {
                let spaces = line.prefix { $0 == " " || $0 == "\t" }
                indent = String(spaces)
                marker = nil
                rest = String(line.dropFirst(spaces.count))
            }
        }
    }
}
