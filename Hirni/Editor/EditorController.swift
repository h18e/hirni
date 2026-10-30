import HirniKit
import Observation

#if os(iOS)
import UIKit
typealias PlatformTextView = UITextView
#else
import AppKit
typealias PlatformTextView = NSTextView
#endif

/// Verbindet die Formatierungsknöpfe (Leiste, Toolbar, Tastenkürzel) mit der
/// Textansicht. Die eigentliche Textlogik steckt in `HirniKit.MarkdownEditing`.
@Observable
final class EditorController {
    /// Passende Tags, während `#…` getippt wird.
    private(set) var suggestions: [String] = []

    /// Anhang, der gerade in der Vorschau (QuickLook) offen ist.
    var previewURL: URL?

    /// Welche Auswahl für einen neuen Anhang geöffnet werden soll (iPhone-Leiste).
    var attachmentRequest: AttachmentSource?
    /// Auswahl «Datenbank einfügen» ist offen.
    var showsDatabasePicker = false

    enum AttachmentSource: Identifiable {
        case photos
        case camera
        case files
        var id: Self { self }
    }

    /// Bilder und Datenbank-Ansichten unter ihren Zeilen anzeigen.
    @ObservationIgnored let overlays = EmbedOverlays()
    /// Automatisches Speichern kurz nach der letzten Eingabe (siehe NoteEditorView).
    @ObservationIgnored var autosave: Task<Void, Never>?
    /// Mac: Dateien wurden in den Text gezogen.
    @ObservationIgnored var onFileDrop: (([URL]) -> Void)?

    init() {
        overlays.onTap = { [weak self] url in self?.previewURL = url }
        // Änderungen im Tabellen-Raster zurück in den Markdown-Text.
        overlays.tables.onChange = { [weak self] index, table in self?.replaceTable(at: index, with: table) }
        #if os(iOS)
        overlays.tables.onDragging = { [weak self] dragging in
            self?.textView?.panGestureRecognizer.isEnabled = !dragging
        }
        #endif
    }

    /// Alle bekannten Tags im hirni-Ordner, die häufigsten zuerst.
    @ObservationIgnored var knownTags: [String] = []
    @ObservationIgnored weak var textView: PlatformTextView? {
        didSet {
            if let pendingText { setText(pendingText) }
        }
    }
    /// Wird nach jeder Änderung durch einen Befehl aufgerufen.
    @ObservationIgnored var onTextChange: ((String) -> Void)?
    /// Text, der gesetzt wurde, bevor die Textansicht bereit war.
    @ObservationIgnored private var pendingText: String?

    /// Ersetzt den ganzen Text von aussen (Datei geladen oder anderswo geändert).
    ///
    /// Das ist der einzige Weg, auf dem Text in die Textansicht hineinkommt.
    /// Eingaben fliessen nur hinaus (über die Bindung). Würde SwiftUI den Text
    /// bei jeder Aktualisierung zurückschreiben, käme manchmal ein veralteter
    /// Stand an, und der Cursor spränge zurück.
    func setText(_ text: String) {
        guard let textView else {
            pendingText = text
            return
        }
        pendingText = nil
        #if os(iOS)
        guard textView.text != text else { return }
        let selection = textView.selectedRange
        textView.text = text
        textView.selectedRange = NSRange(location: min(selection.location, (text as NSString).length), length: 0)
        #else
        guard textView.string != text else { return }
        let selection = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        #endif
        updateSuggestions()
    }

    // MARK: - Befehle

    func bold() { perform { MarkdownEditing.toggleWrap("**", in: $0, selection: $1) } }
    func italic() { perform { MarkdownEditing.toggleWrap("*", in: $0, selection: $1) } }
    func heading() { perform { MarkdownEditing.cycleHeading(in: $0, selection: $1) } }
    func bulletList() { perform { MarkdownEditing.toggleLineStyle(.bullet, in: $0, selection: $1) } }
    func checklist() { perform { MarkdownEditing.toggleLineStyle(.checkbox, in: $0, selection: $1) } }

    /// Fügt einen eingebetteten Anhang auf einer eigenen Zeile ein.
    func insertBlock(_ markdown: String) {
        perform { MarkdownEditing.insertBlock(markdown, in: $0, selection: $1) }
    }

    /// Ersetzt im Text den `hirni-db`-Block, der `embed` entspricht (gleiche
    /// Datenbank und Ansicht), z. B. nach dem Wechsel der Ansicht im Kasten.
    func replaceDatabaseBlock(_ embed: DatabaseEmbed, with markdown: String) {
        perform(keepingScroll: true) { text, selection in
            let key = EmbeddedDatabases.key(embed)
            guard let block = DatabaseEmbed.blocks(in: text).first(where: { EmbeddedDatabases.key($0) == key }) else {
                return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "", selection: selection)
            }
            // Ohne die schliessende Zeilenschaltung: Sie bleibt stehen.
            var range = block.range
            if (text as NSString).substring(with: range).hasSuffix("\n") { range.length -= 1 }
            let delta = (markdown as NSString).length - range.length
            let caret = selection.location >= NSMaxRange(range) ? selection.location + delta : selection.location
            return TextEdit(range: range, replacement: markdown, selection: NSRange(location: max(0, caret), length: 0))
        }
    }

    /// Fügt eine neue, leere Tabelle (3 Spalten, 2 Zeilen) auf eigenen Zeilen ein.
    /// Davor und danach eine Leerzeile, sonst lesen andere Programme
    /// (z. B. Obsidian) die Tabelle als Fortsetzung des Absatzes.
    func insertTable() {
        perform { text, selection in
            let ns = text as NSString
            let lineStart = ns.lineRange(for: NSRange(location: selection.location, length: 0)).location
            let previous = lineStart > 0 ? ns.lineRange(for: NSRange(location: lineStart - 1, length: 0)) : nil
            let previousIsEmpty = previous.map { ns.substring(with: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? true
            let atLineStart = selection.location == lineStart
            let prefix = (atLineStart ? "" : "\n") + ((atLineStart && previousIsEmpty) ? "" : "\n")
            let insertion = prefix + MarkdownTable.empty().markdown + "\n\n"
            return TextEdit(range: selection, replacement: insertion,
                            selection: NSRange(location: selection.location + (insertion as NSString).length, length: 0))
        }
    }

    private func replaceTable(at index: Int, with table: MarkdownTable) {
        perform(keepingScroll: true) { text, selection in
            let tables = MarkdownTable.tables(in: text)
            guard tables.indices.contains(index) else {
                return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "", selection: selection)
            }
            let range = tables[index].range
            let markdown = table.markdown
            let delta = (markdown as NSString).length - range.length
            let caret = selection.location >= NSMaxRange(range) ? selection.location + delta : min(selection.location, range.location)
            return TextEdit(range: range, replacement: markdown, selection: NSRange(location: max(0, caret), length: 0))
        }
    }

    func insertTag() {
        perform { text, selection in
            // Vor dem # ein Leerzeichen, falls direkt davor ein Wort steht.
            let ns = text as NSString
            let needsSpace = selection.location > 0
                && !(ns.substring(with: NSRange(location: selection.location - 1, length: 1)).first?.isWhitespace ?? true)
            let insertion = needsSpace ? " #" : "#"
            return TextEdit(
                range: selection, replacement: insertion,
                selection: NSRange(location: selection.location + (insertion as NSString).length, length: 0)
            )
        }
    }

    /// Return in einer Liste: nächsten Punkt beginnen. `false`, wenn Return
    /// normal ausgeführt werden soll.
    func handleReturn() -> Bool {
        guard let text = currentText, let selection = currentSelection,
              let edit = MarkdownEditing.continueList(in: text, selection: selection)
        else { return false }
        apply(edit)
        return true
    }

    /// Link an Position `index`, z. B. zum Öffnen beim Antippen.
    func link(at index: Int) -> URL? {
        guard let text = currentText else { return nil }
        return MarkdownSyntax.link(at: index, in: text)
    }

    /// Tipp/Klick an Position `index`: Liegt dort eine Checkbox, wird sie umgeschaltet.
    func toggleCheckbox(at index: Int) -> Bool {
        guard let text = currentText, let selection = currentSelection,
              let edit = MarkdownEditing.toggleCheckbox(at: index, in: text, keeping: selection)
        else { return false }
        apply(edit)
        return true
    }

    func accept(_ tag: String) {
        guard let text = currentText, let selection = currentSelection,
              let query = MarkdownEditing.tagQuery(in: text, caret: selection.location)
        else { return }
        apply(MarkdownEditing.completeTag(tag, replacing: query.range, in: text))
    }

    /// Nach jeder Eingabe oder Cursorbewegung: Tag-Vorschläge neu bestimmen.
    func updateSuggestions() {
        guard let text = currentText, let selection = currentSelection, selection.length == 0,
              let query = MarkdownEditing.tagQuery(in: text, caret: selection.location)
        else {
            if !suggestions.isEmpty { suggestions = [] }
            return
        }
        let typed = query.query.lowercased()
        let matches = candidates(in: text, excluding: query.range)
            .filter { $0.lowercased().hasPrefix(typed) && $0.lowercased() != typed }
            .prefix(8)
        if suggestions != Array(matches) { suggestions = Array(matches) }
    }

    /// Bekannte Tags aus dem ganzen Ordner, ergänzt um die Tags dieser Notiz
    /// (auch eben erst getippte). Der Tag, der gerade entsteht, zählt nicht mit.
    private func candidates(in text: String, excluding typing: NSRange) -> [String] {
        let rest = (text as NSString).replacingCharacters(in: typing, with: "")
        var seen = Set(knownTags.map { $0.lowercased() })
        var result = knownTags
        for tag in MarkdownSyntax.tags(in: rest) where seen.insert(tag.lowercased()).inserted {
            result.append(tag)
        }
        return result
    }

    #if os(iOS)
    /// Cursor ans Ende des Texts (z. B. nach Return im Titel).
    func focusText() {
        guard let textView else { return }
        textView.becomeFirstResponder()
        textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)
    }

    func dismissKeyboard() {
        textView?.resignFirstResponder()
    }
    #endif

    // MARK: - Vorlagen: Cursor und Beispieltext

    /// Setzt den Cursor an `offset`, oder markiert den Beispieltext dort.
    /// Ohne `offset` den ersten Beispieltext. Wie beim Titel mehrmals
    /// versuchen: Die Textansicht nimmt den Fokus erst an, wenn sie bereit ist.
    func placeCursor(at offset: Int?) async {
        for _ in 0..<15 {
            if let textView, let text = currentText, Self.isReady(textView) {
                var range: NSRange
                if let offset {
                    range = NSRange(location: min(offset, (text as NSString).length), length: 0)
                } else if let first = TemplateFiller.hintPattern.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
                    range = first.range
                } else {
                    return
                }
                if let hint = TemplateFiller.hintRange(containing: range.location, in: text), range.length == 0, range.location > hint.location {
                    range = hint
                }
                #if os(iOS)
                textView.becomeFirstResponder()
                textView.selectedRange = range
                textView.scrollRangeToVisible(range)
                if textView.isFirstResponder { return }
                #else
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(range)
                textView.scrollRangeToVisible(range)
                if textView.window?.firstResponder === textView { return }
                #endif
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    private static func isReady(_ textView: PlatformTextView) -> Bool {
        textView.window != nil
    }

    @ObservationIgnored private var replacingHint = false
    /// In Vorlagen sind Beispieltexte gewöhnlicher Text zum Bearbeiten.
    @ObservationIgnored var hintsAsText = false

    /// Tippen oder Löschen in einem Beispieltext (`{{? Thema}}`) ersetzt ihn
    /// ganz, egal wo genau der Cursor steht. `true` = erledigt, die Textansicht
    /// soll die Eingabe nicht selbst einfügen.
    func replaceHint(in range: NSRange, with replacement: String) -> Bool {
        guard !replacingHint, !hintsAsText, let text = currentText, text.contains("{{?") else { return false }
        let ns = text as NSString
        for match in TemplateFiller.hintPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let hint = match.range
            let touches = range.length == 0
                ? range.location >= hint.location && range.location < NSMaxRange(hint)
                : NSIntersectionRange(range, hint).length > 0
            guard touches else { continue }
            // Ein Zeilenumbruch im Beispieltext soll ihn nicht leeren, sondern danach umbrechen.
            if replacement == "\n" { return false }
            let target = NSUnionRange(hint, range)
            replacingHint = true
            defer { replacingHint = false }
            apply(TextEdit(range: target, replacement: replacement,
                           selection: NSRange(location: target.location + (replacement as NSString).length, length: 0)))
            return true
        }
        return false
    }

    /// Steht der Cursor in einem Beispieltext (`{{? Thema}}`), wird er ganz
    /// markiert: Was man tippt, ersetzt ihn.
    func selectHintIfNeeded() {
        guard !hintsAsText, let text = currentText, let selection = currentSelection, selection.length == 0,
              let hint = TemplateFiller.hintRange(containing: selection.location, in: text),
              selection.location > hint.location, selection.location < NSMaxRange(hint)
        else { return }
        DispatchQueue.main.async { [weak self] in
            guard let textView = self?.textView else { return }
            #if os(iOS)
            textView.selectedRange = hint
            #else
            textView.setSelectedRange(hint)
            #endif
        }
    }

    // MARK: - Anwenden

    private func perform(keepingScroll: Bool = false, _ makeEdit: (String, NSRange) -> TextEdit) {
        guard let text = currentText, let selection = currentSelection else { return }
        apply(makeEdit(text, selection), keepingScroll: keepingScroll)
    }

    /// Ändert den Text so, dass Rückgängig (⌘Z / Schütteln) funktioniert.
    /// `keepingScroll`: Die Änderung kommt aus einer eingebetteten Ansicht
    /// (Tabelle, Datenbank), nicht vom Tippen im Text. Dann springt die Ansicht
    /// nicht zum Cursor, der Fokus bleibt, wo er ist, und iOS wendet keine
    /// Tipp-Korrekturen an (sonst würde aus `---` ein Gedankenstrich).
    func apply(_ edit: TextEdit, keepingScroll: Bool = false) {
        guard let textView else { return }
        #if os(iOS)
        let offset = textView.contentOffset
        defer {
            if keepingScroll {
                // Die Textansicht scrollt nach einer Änderung verzögert zum
                // Cursor, darum auch danach nochmals zurücksetzen.
                textView.layoutIfNeeded()
                textView.setContentOffset(offset, animated: false)
                for delay in [0.0, 0.1, 0.3] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak textView] in
                        textView?.setContentOffset(offset, animated: false)
                    }
                }
            }
        }
        #else
        let visible = textView.visibleRect.origin
        defer {
            if keepingScroll {
                textView.scroll(visible)
                DispatchQueue.main.async { [weak textView] in textView?.scroll(visible) }
            }
        }
        #endif
        #if os(iOS)
        if keepingScroll {
            textView.textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
            if textView.isFirstResponder { textView.selectedRange = edit.selection }
            if let currentText { onTextChange?(currentText) }
            return
        }
        guard let start = textView.position(from: textView.beginningOfDocument, offset: edit.range.location),
              let end = textView.position(from: start, offset: edit.range.length),
              let range = textView.textRange(from: start, to: end)
        else { return }
        textView.replace(range, withText: edit.replacement)
        textView.selectedRange = edit.selection
        #else
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        if !keepingScroll || textView.window?.firstResponder === textView { textView.setSelectedRange(edit.selection) }
        #endif
        if let currentText { onTextChange?(currentText) }
        updateSuggestions()
    }

    private var currentText: String? {
        #if os(iOS)
        textView?.text
        #else
        textView?.string
        #endif
    }

    private var currentSelection: NSRange? {
        #if os(iOS)
        textView?.selectedRange
        #else
        textView?.selectedRange()
        #endif
    }
}
