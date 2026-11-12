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
    private(set) var suggestions: [String] = [] {
        didSet { parent?.suggestions = suggestions }
    }

    /// Auswahl «Link auf Notiz» ist offen.
    var showsNotePicker = false

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

    /// Fokus in dieser Spalte gesetzt oder verloren.
    ///
    /// Beim Verlieren bleibt die Spalte aktiv: Das Fotos-Blatt oder der Dateidialog
    /// nimmt ihr den Fokus, das Gewählte soll aber trotzdem dort landen.
    func focusChanged(_ focused: Bool) {
        guard focused else { return }
        if let parent {
            parent.activeColumn = self
        } else {
            activeColumn = nil
        }
    }

    /// Anderer Text von aussen: Die gemerkte Spalte gilt nur weiter, wenn dort
    /// wirklich der Cursor steht. Sonst landeten Befehle in einer falschen Spalte.
    /// Lädt die App bloss denselben Text neu (etwa nach dem iCloud-Abgleich),
    /// bleibt alles, wie es ist.
    private func releaseUnfocusedColumn() {
        #if os(iOS)
        if activeColumn?.textView?.isFirstResponder != true { activeColumn = nil }
        #else
        if let view = activeColumn?.textView, view.window?.firstResponder === view { return }
        activeColumn = nil
        #endif
    }

    /// Die Spalte gibt es nicht mehr.
    func columnRemoved(_ column: EditorController) {
        if activeColumn === column { activeColumn = nil }
    }

    /// Spalte: Der Notiz melden, wie viel Platz der Inhalt braucht.
    func reportContentHeight() {
        guard let onContentHeight, let textView else { return }
        #if os(iOS)
        let padding = textView.textContainerInset.top + textView.textContainerInset.bottom
        // Ohne eigenes Scrollen endet der Textbereich an der Ansicht: Das Layout
        // allein kennt die wirkliche Länge also nicht.
        let width = textView.bounds.width
        guard width > 0 else { return }
        let used = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height - padding
        #else
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).maxY
        let padding = 2 * textView.textContainerInset.height
        #endif
        onContentHeight(ceil(max(used + padding, overlays.contentBottom + padding / 2)))
    }

    /// Spalte: Die Spalte scrollt nicht selbst, also muss die Notiz den Cursor zeigen.
    func revealCaretInNote() {
        guard let note = parent?.textView else { return }
        DispatchQueue.main.async { [weak self] in
            guard let textView = self?.textView else { return }
            #if os(iOS)
            guard textView.isFirstResponder, let end = textView.selectedTextRange?.end else { return }
            let caret = textView.convert(textView.caretRect(for: end), to: note)
            note.scrollRectToVisible(caret.insetBy(dx: 0, dy: -24), animated: false)
            #else
            guard textView.window?.firstResponder === textView, let layout = textView.layoutManager,
                  let container = textView.textContainer else { return }
            let glyph = layout.glyphRange(forCharacterRange: NSRange(location: textView.selectedRange().location, length: 0), actualCharacterRange: nil)
            let caret = layout.boundingRect(forGlyphRange: glyph, in: container)
                .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            note.scrollToVisible(textView.convert(caret, to: note).insetBy(dx: 0, dy: -24))
            #endif
        }
    }

    /// Bilder und Datenbank-Ansichten unter ihren Zeilen anzeigen.
    @ObservationIgnored let overlays = EmbedOverlays()
    /// Automatisches Speichern kurz nach der letzten Eingabe (siehe NoteEditorView).
    @ObservationIgnored var autosave: Task<Void, Never>?
    /// Das Laden der Notiz. Mehrere Wechsel kurz hintereinander laufen nacheinander.
    @ObservationIgnored var loading: Task<Void, Never>?
    /// Ein Link auf eine Notiz wurde angetippt.
    @ObservationIgnored var onInternalLink: ((URL) -> Void)?
    /// Mac: Dateien wurden in den Text gezogen.
    @ObservationIgnored var onFileDrop: (([URL]) -> Void)?

    /// Die Notiz, wenn dieser Editor eine Spalte ist (siehe `NoteColumns`).
    @ObservationIgnored private weak var parent: EditorController?
    /// Die Spalte mit dem Cursor: Formatknöpfe wirken dort.
    @ObservationIgnored private var activeColumn: EditorController?
    /// Spalte: Die nötige Höhe hat sich geändert.
    @ObservationIgnored var onContentHeight: ((CGFloat) -> Void)?

    /// Empfänger der Knöpfe. Bei Spalten ist das die Notiz: Dort hängen die
    /// Blätter, und sie leitet die Befehle an die Spalte mit dem Cursor weiter.
    var commandController: EditorController { parent ?? self }

    init(parent: EditorController? = nil) {
        self.parent = parent
        if let parent {
            overlays.resolve = { [weak parent] in parent?.overlays.resolve($0) }
            overlays.onTap = { [weak parent] in parent?.previewURL = $0 }
            onInternalLink = { [weak parent] in parent?.onInternalLink?($0) }
            onFileDrop = { [weak parent] in parent?.onFileDrop?($0) }
            hintsAsText = parent.hintsAsText
            overlays.tables.hintsAsText = parent.hintsAsText
        } else {
            overlays.onTap = { [weak self] url in self?.previewURL = url }
        }
        overlays.columns.owner = self
        overlays.columns.onChange = { [weak self] index, block in self?.replaceColumns(at: index, with: block.markdown) }
        overlays.columns.onDissolve = { [weak self] index in self?.dissolveColumns(at: index) }
        // Änderungen im Tabellen-Raster zurück in den Markdown-Text.
        overlays.tables.onChange = { [weak self] index, table in self?.replaceTable(at: index, with: table) }
        overlays.tables.onRemove = { [weak self] index in self?.removeTable(at: index) }
        overlays.tables.onTab = { [weak self] index, cell in self?.tab(inTable: index, from: cell) }
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
        releaseUnfocusedColumn()
        let selection = textView.selectedRange
        textView.text = text
        textView.selectedRange = NSRange(location: min(selection.location, (text as NSString).length), length: 0)
        #else
        guard textView.string != text else { return }
        releaseUnfocusedColumn()
        let selection = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        #endif
        updateSuggestions()
    }

    // MARK: - Befehle

    func bold() { perform { MarkdownEditing.toggleWrap("**", in: $0, selection: $1) } }
    func italic() { perform { MarkdownEditing.toggleWrap("*", in: $0, selection: $1) } }
    func underline() { perform { MarkdownEditing.toggleTag("u", in: $0, selection: $1) } }
    func strikethrough() { perform { MarkdownEditing.toggleWrap("~~", in: $0, selection: $1) } }
    func highlight() { perform { MarkdownEditing.toggleTag("mark", in: $0, selection: $1) } }
    func setColor(_ color: TextColor?) { perform { MarkdownEditing.setColor(color, in: $0, selection: $1) } }
    func heading() { perform { MarkdownEditing.cycleHeading(in: $0, selection: $1) } }
    func bulletList() { perform { MarkdownEditing.toggleLineStyle(.bullet, in: $0, selection: $1) } }
    func checklist() { perform { MarkdownEditing.cycleChecklist(in: $0, selection: $1) } }

    /// Fügt einen eingebetteten Anhang auf einer eigenen Zeile ein.
    func insertBlock(_ markdown: String) {
        perform { MarkdownEditing.insertBlock(markdown, in: $0, selection: $1) }
    }

    /// Fügt einen Bereich mit zwei Spalten ein. Markierter Text kommt in die
    /// erste Spalte. Spalten in Spalten gibt es nicht.
    func insertColumns() {
        guard parent == nil, activeColumn == nil else { return }
        perform { text, selection in
            var block = ColumnBlock.empty()
            block.columns[0] = (text as NSString).substring(with: selection)
            return MarkdownEditing.insertBlock(block.markdown + "\n", in: text, selection: selection)
        }
        guard let text = currentText, let caret = currentSelection?.location,
              let index = ColumnBlock.blocks(in: text).lastIndex(where: { $0.range.location < caret })
        else { return }
        // Die Spalten entstehen beim nächsten Layout.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }
            let column = self.overlays.columns.model(at: index).columns.first?.controller
            let length = (column?.currentText as NSString?)?.length ?? 0
            column?.selectInText(NSRange(location: length, length: 0))
        }
    }

    private func replaceColumns(at index: Int, with markdown: String) {
        perform(keepingScroll: true) { text, selection in
            let blocks = ColumnBlock.blocks(in: text)
            guard blocks.indices.contains(index) else {
                return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "", selection: selection)
            }
            let range = blocks[index].range
            let delta = (markdown as NSString).length - range.length
            let caret = selection.location >= NSMaxRange(range) ? selection.location + delta : min(selection.location, range.location)
            return TextEdit(range: range, replacement: markdown, selection: NSRange(location: max(0, caret), length: 0))
        }
    }

    /// Macht aus dem Bereich wieder gewöhnlichen Text.
    private func dissolveColumns(at index: Int) {
        guard let text = currentText else { return }
        let blocks = ColumnBlock.blocks(in: text)
        guard blocks.indices.contains(index) else { return }
        let block = blocks[index]
        activeColumn = nil
        replaceColumns(at: index, with: block.dissolved)
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

    private func removeTable(at index: Int) {
        perform(keepingScroll: true) { text, selection in
            let tables = MarkdownTable.tables(in: text)
            guard tables.indices.contains(index) else {
                return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "", selection: selection)
            }
            return tables[index].removal(in: text, selection: selection)
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
        if let activeColumn { return activeColumn.accept(tag) }
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
        let known = parent?.knownTags ?? knownTags
        var seen = Set(known.map { $0.lowercased() })
        var result = known
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
        activeColumn?.dismissKeyboard()
        textView?.resignFirstResponder()
    }
    #endif

    /// Lese-Modus: Der Editor ist verborgen und darf keine Eingaben mehr annehmen.
    func endEditing() {
        #if os(iOS)
        dismissKeyboard()
        #else
        if let window = textView?.window { window.makeFirstResponder(nil) }
        #endif
    }

    // MARK: - Links auf Notizen

    /// Die Auswahl wird zur eigenen Beschriftung des Links.
    var selectedText: String? {
        if let activeColumn { return activeColumn.selectedText }
        guard let text = currentText, let selection = currentSelection, selection.length > 0 else { return nil }
        let selected = (text as NSString).substring(with: selection)
        return selected.contains("\n") ? nil : selected
    }

    func insertNoteLink(_ markdown: String) {
        perform { _, selection in
            TextEdit(range: selection, replacement: markdown,
                     selection: NSRange(location: selection.location + (markdown as NSString).length, length: 0))
        }
    }

    /// Löschen in ausgeblendeten Zeichen: Ein Notiz-Link verschwindet als
    /// Ganzes, bei Formaten fällt das Format weg, der Text bleibt.
    func deleteHiddenMarks(in range: NSRange) -> Bool {
        guard !replacingHint, let text = currentText, text.contains("<") || text.contains("hirni:") else { return false }
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: range.location, length: 0))
        func inMarks(_ inner: NSRange, of whole: NSRange) -> Bool {
            NSIntersectionRange(range, whole).length > 0 && NSIntersectionRange(range, inner).length == 0
        }
        func replace(_ whole: NSRange, with replacement: String) {
            replacingHint = true
            defer { replacingHint = false }
            apply(TextEdit(range: whole, replacement: replacement,
                           selection: NSRange(location: whole.location + (replacement as NSString).length, length: 0)))
        }
        for m in NoteLink.pattern.matches(in: text, range: line) where inMarks(m.range(at: 1), of: m.range) {
            replace(m.range, with: "")
            return true
        }
        let plain = MarkdownSyntax.plainText(ns.substring(with: range))
        guard plain.isEmpty || plain == ns.substring(with: range) else { return false }
        for span in MarkdownSyntax.spans(in: ns.substring(with: line)) where span.kind == .hiddenMarker {
            let hidden = NSRange(location: line.location + span.range.location, length: span.range.length)
            guard NSIntersectionRange(range, hidden).length > 0 else { continue }
            let lineText = ns.substring(with: line)
            let stripped = MarkdownSyntax.removingFormat(at: span.range.location, in: lineText)
            guard stripped != lineText else { return false }
            replace(line, with: stripped)
            return true
        }
        return false
    }

    // MARK: - Inhaltsverzeichnis

    var headings: [MarkdownSyntax.Heading] {
        currentText.map(MarkdownSyntax.headings(in:)) ?? []
    }

    /// Springt zur Überschrift: Sie steht danach zuoberst.
    func jump(to heading: MarkdownSyntax.Heading) {
        guard let textView, let text = currentText, heading.location <= (text as NSString).length else { return }
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: heading.location, length: 0))
        let end = NSMaxRange(line) - (ns.substring(with: line).hasSuffix("\n") ? 1 : 0)
        let target = NSRange(location: heading.location, length: max(end - heading.location, 0))
        #if os(iOS)
        // Beim Lesen bleibt die Tastatur zu: den Cursor nur setzen, wenn sie offen ist.
        if textView.isFirstResponder { textView.selectedRange = NSRange(location: end, length: 0) }
        let layout = textView.layoutManager
        layout.ensureLayout(forCharacterRange: NSRange(location: 0, length: NSMaxRange(target)))
        let glyphs = layout.glyphRange(forCharacterRange: target, actualCharacterRange: nil)
        let top = layout.boundingRect(forGlyphRange: glyphs, in: textView.textContainer).minY + textView.textContainerInset.top
        let inset = textView.adjustedContentInset
        let lowest = max(-inset.top, textView.contentSize.height - textView.bounds.height + inset.bottom)
        textView.setContentOffset(CGPoint(x: 0, y: min(lowest, max(-inset.top, top - 8))), animated: true)
        #else
        textView.setSelectedRange(NSRange(location: end, length: 0))
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        layout.ensureLayout(forCharacterRange: NSRange(location: 0, length: NSMaxRange(target)))
        let glyphs = layout.glyphRange(forCharacterRange: target, actualCharacterRange: nil)
        let top = layout.boundingRect(forGlyphRange: glyphs, in: container).minY + textView.textContainerOrigin.y
        textView.scroll(NSPoint(x: 0, y: max(0, top - 8)))
        textView.window?.makeFirstResponder(textView)
        #endif
    }

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
                if focusCell(at: range.location, in: text) { return }
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
    @ObservationIgnored var hintsAsText = false {
        didSet {
            overlays.tables.hintsAsText = hintsAsText
            for column in overlays.columns.controllers { column.hintsAsText = hintsAsText }
        }
    }

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

    /// Tab: zum nächsten Beispieltext nach der Auswahl springen und ihn
    /// markieren, nach dem letzten wieder zum ersten. Ohne Beispieltext
    /// passiert nichts (ein Tabulatorzeichen gibt es mit Shift+Tab).
    func jumpToNextHint() {
        guard let textView, let text = currentText, let selection = currentSelection else { return }
        let hints = TemplateFiller.hintPattern
            .matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            .map(\.range)
        // Aus einer Spalte geht es nach ihrem letzten Beispieltext in der Notiz weiter.
        guard let target = hints.first(where: { $0.location >= NSMaxRange(selection) && $0 != selection })
            ?? (parent == nil ? hints.first : nil)
        else {
            parent?.jumpToNextHint(after: self)
            return
        }
        if focusCell(at: target.location, in: text) { return }
        #if os(iOS)
        textView.selectedRange = target
        #else
        textView.setSelectedRange(target)
        #endif
        textView.scrollRangeToVisible(target)
    }

    private func jumpToNextHint(after column: EditorController) {
        guard let text = currentText, let position = overlays.columns.position(of: column) else { return }
        let blocks = ColumnBlock.blocks(in: text)
        guard blocks.indices.contains(position.block), blocks[position.block].columnRanges.indices.contains(position.column)
        else { return }
        let end = NSMaxRange(blocks[position.block].columnRanges[position.column])
        let hints = TemplateFiller.hintPattern
            .matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            .map(\.range)
        guard let target = hints.first(where: { $0.location > end }) ?? hints.first else { return }
        if !focusCell(at: target.location, in: text) { selectInText(target) }
    }

    /// Aus dem Titel weiter in den Text (Tab bzw. Return): zum ersten
    /// Beispieltext, ohne Beispieltext ans Ende.
    func focusFirstHint() {
        guard let textView, let text = currentText else { return }
        let length = (text as NSString).length
        let target = TemplateFiller.hintPattern.firstMatch(in: text, range: NSRange(location: 0, length: length))?.range
            ?? NSRange(location: length, length: 0)
        if focusCell(at: target.location, in: text) { return }
        #if os(iOS)
        textView.becomeFirstResponder()
        textView.selectedRange = target
        #else
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(target)
        #endif
        textView.scrollRangeToVisible(target)
    }

    /// Tab in einer Tabellenzelle: zum nächsten Beispieltext, nicht einfach
    /// zur nächsten Zelle.
    private func tab(inTable index: Int, from cell: TableCell) {
        guard let text = currentText else { return }
        let tables = MarkdownTable.tables(in: text)
        guard tables.indices.contains(index) else { return }
        let table = tables[index]
        switch table.tabTarget(fromRow: cell.row, column: cell.column, in: text) {
        case .hint(let hint):
            if !focusCell(at: hint.location, in: text) { selectInText(hint) }
        case .cell(let row, let column):
            overlays.tables.model(at: index).focusRequest = TableCell(row: row, column: column)
        case .afterTable:
            selectInText(NSRange(location: min(NSMaxRange(table.range) + 1, (text as NSString).length), length: 0))
        }
    }

    /// Fokus in den Text, Auswahl setzen.
    private func selectInText(_ range: NSRange) {
        guard let textView else { return }
        #if os(iOS)
        textView.becomeFirstResponder()
        textView.selectedRange = range
        #else
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(range)
        #endif
        textView.scrollRangeToVisible(range)
    }

    /// Liegt `location` in einer Tabelle, kommt die Zelle in den Fokus: Der Text
    /// der Tabelle selbst ist ausgeblendet, man bearbeitet sie im Raster.
    private func focusCell(at location: Int, in text: String) -> Bool {
        for (index, table) in MarkdownTable.tables(in: text).enumerated() {
            guard let cell = table.cell(at: location, in: text) else { continue }
            textView?.scrollRangeToVisible(table.range)
            overlays.tables.model(at: index).focusRequest = TableCell(row: cell.row, column: cell.column)
            return true
        }
        for (index, block) in ColumnBlock.blocks(in: text).enumerated() {
            guard let position = block.column(at: location) else { continue }
            let columns = overlays.columns.model(at: index).columns
            guard columns.indices.contains(position.index) else { return false }
            textView?.scrollRangeToVisible(block.range)
            let column = columns[position.index].controller
            let columnText = block.columns[position.index]
            if !column.focusCell(at: position.offset, in: columnText) {
                let hint = TemplateFiller.hintRange(containing: position.offset, in: columnText)
                column.selectInText(hint ?? NSRange(location: position.offset, length: 0))
            }
            return true
        }
        return false
    }

    /// Shift+Tab: ein Tabulatorzeichen einfügen.
    func insertTabCharacter() {
        perform { _, selection in
            TextEdit(range: selection, replacement: "\t", selection: NSRange(location: selection.location + 1, length: 0))
        }
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
        // Befehle gehen an die Spalte mit dem Cursor. Änderungen aus
        // eingebetteten Ansichten betreffen immer diesen Text selbst.
        if !keepingScroll, let activeColumn { return activeColumn.perform(makeEdit) }
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
