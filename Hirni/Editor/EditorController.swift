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
    /// Mac: Dateien wurden in den Text gezogen.
    @ObservationIgnored var onFileDrop: (([URL]) -> Void)?

    init() {
        overlays.onTap = { [weak self] url in self?.previewURL = url }
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
    func dismissKeyboard() {
        textView?.resignFirstResponder()
    }
    #endif

    // MARK: - Anwenden

    private func perform(_ makeEdit: (String, NSRange) -> TextEdit) {
        guard let text = currentText, let selection = currentSelection else { return }
        apply(makeEdit(text, selection))
    }

    /// Ändert den Text so, dass Rückgängig (⌘Z / Schütteln) funktioniert.
    func apply(_ edit: TextEdit) {
        guard let textView else { return }
        #if os(iOS)
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
        textView.setSelectedRange(edit.selection)
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
