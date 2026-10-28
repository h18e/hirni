import HirniKit

#if os(iOS)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

/// Färbt und formatiert den Text im Editor anhand der erkannten Markdown-Bereiche.
/// Die Markdown-Zeichen bleiben sichtbar, aber grau.
enum MarkdownStyler {
    static var bodyFont: PlatformFont {
        #if os(iOS)
        .preferredFont(forTextStyle: .body)
        #else
        .systemFont(ofSize: 14)
        #endif
    }

    /// Überschriften 1–6, relativ zur normalen Schrift.
    private static let headingScale: [CGFloat] = [1.6, 1.35, 1.15, 1.05, 1, 1]

    /// `reservedHeight` liefert pro eingebettetem Anhang den Platz, der unter
    /// seiner Zeile für das Bild frei bleiben soll (siehe `EmbedOverlays`).
    /// `databaseHeight` dasselbe für eingebettete Datenbanken (`hirni-db`).
    static func apply(
        to storage: NSTextStorage,
        reservedHeight: (String) -> CGFloat = { _ in 0 },
        databaseHeight: (DatabaseEmbed) -> CGFloat = { _ in 0 },
        tableHeight: (MarkdownTable) -> CGFloat = { _ in 0 }
    ) {
        let text = storage.string
        let full = NSRange(location: 0, length: storage.length)
        let base = bodyFont

        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: Colors.text], range: full)

        let spans = MarkdownSyntax.spans(in: text)
        // Erst ganze Zeilen, dann Inline-Formatierung, zuletzt die grauen Zeichen.
        for span in spans where span.kind.isLineLevel { style(span, in: storage, base: base) }
        for span in spans where !span.kind.isLineLevel && span.kind != .syntax { style(span, in: storage, base: base) }
        for span in spans where span.kind == .syntax { style(span, in: storage, base: base) }

        for span in spans {
            guard case .embed(let path) = span.kind else { continue }
            let height = reservedHeight(path)
            guard height > 0 else { continue }
            let paragraph = (text as NSString).paragraphRange(for: span.range)
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = height
            storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
        }

        // Datenbank-Blöcke: klein und grau, die Ansicht erscheint darunter.
        for embed in DatabaseEmbed.blocks(in: text) where NSMaxRange(embed.range) <= storage.length {
            storage.removeAttribute(.backgroundColor, range: embed.range)
            storage.addAttributes([
                .font: PlatformFont.monospacedSystemFont(ofSize: base.pointSize * 0.75, weight: .regular),
                .foregroundColor: Colors.syntax,
            ], range: embed.range)
            let height = databaseHeight(embed)
            guard height > 0 else { continue }
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = height
            storage.addAttribute(.paragraphStyle, value: style, range: (text as NSString).paragraphRange(for: embed.closingLine))
        }
        // Markdown-Tabellen: Text unsichtbar und fast ohne Höhe, darüber
        // liegt das Raster. Unter der letzten Zeile bleibt Platz dafür.
        for table in MarkdownTable.tables(in: text) where NSMaxRange(table.range) <= storage.length {
            let height = tableHeight(table)
            guard height > 0 else { continue }
            storage.removeAttribute(.link, range: table.range)
            storage.addAttributes([
                .font: PlatformFont.systemFont(ofSize: 0.1),
                .foregroundColor: PlatformColor.clear,
                .backgroundColor: PlatformColor.clear,
            ], range: table.range)
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = height + 8
            let last = (text as NSString).paragraphRange(for: NSRange(location: NSMaxRange(table.range) - 1, length: 0))
            storage.addAttribute(.paragraphStyle, value: style, range: last)
        }
        storage.endEditing()
    }

    private static func style(_ span: MarkdownSpan, in storage: NSTextStorage, base: PlatformFont) {
        let range = span.range
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }

        switch span.kind {
        case .heading(let level):
            let size = base.pointSize * headingScale[min(level, 6) - 1]
            storage.addAttribute(.font, value: font(base, size: size, bold: true), range: range)
        case .codeBlock:
            storage.addAttributes([
                .font: PlatformFont.monospacedSystemFont(ofSize: base.pointSize * 0.92, weight: .regular),
                .backgroundColor: Colors.codeBackground,
            ], range: range)
        case .quote:
            storage.addAttribute(.foregroundColor, value: Colors.secondary, range: range)
            addTraits(italic: true, in: range, of: storage)
        case .bold:
            addTraits(bold: true, in: range, of: storage)
        case .italic:
            addTraits(italic: true, in: range, of: storage)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .inlineCode:
            storage.addAttributes([
                .font: PlatformFont.monospacedSystemFont(ofSize: base.pointSize * 0.92, weight: .regular),
                .backgroundColor: Colors.codeBackground,
            ], range: range)
        case .listMarker:
            storage.addAttribute(.foregroundColor, value: Colors.secondary, range: range)
        case .hiddenMarker:
            // Fast ohne Breite und unsichtbar: Vor der Checkbox steht kein Strich.
            storage.addAttributes([
                .font: PlatformFont.systemFont(ofSize: 0.1),
                .foregroundColor: PlatformColor.clear,
            ], range: range)
        case .checkbox:
            storage.addAttributes([
                .foregroundColor: Colors.accent,
                .font: PlatformFont.monospacedSystemFont(ofSize: base.pointSize, weight: .semibold),
            ], range: range)
        case .doneItem:
            storage.addAttributes([
                .foregroundColor: Colors.secondary,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            ], range: range)
        case .link(let address):
            storage.addAttributes([
                .foregroundColor: Colors.accent,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: range)
            #if os(macOS)
            // Am Mac öffnet ein Klick den Link (Zeiger wird zur Hand).
            if let url = MarkdownSyntax.linkURL(address) { storage.addAttribute(.link, value: url, range: range) }
            #endif
        case .tag:
            storage.addAttributes([
                .foregroundColor: Colors.accent,
                .backgroundColor: Colors.tagBackground,
            ], range: range)
        case .syntax:
            storage.addAttribute(.foregroundColor, value: Colors.syntax, range: range)
        case .taskDate:
            storage.addAttributes([
                .foregroundColor: Colors.syntax,
                .font: PlatformFont.systemFont(ofSize: base.pointSize * 0.75),
            ], range: range)
        case .embed:
            // Der Verweis selbst ist nur grau (über `.syntax`), das Bild kommt darunter.
            storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: base.pointSize * 0.8), range: range)
        }
    }

    /// Fett/kursiv zur bestehenden Schrift hinzufügen (z. B. fett in einer Überschrift).
    private static func addTraits(bold: Bool = false, italic: Bool = false, in range: NSRange, of storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let current = (value as? PlatformFont) ?? bodyFont
            storage.addAttribute(.font, value: font(current, size: current.pointSize, bold: bold, italic: italic), range: subrange)
        }
    }

    private static func font(_ base: PlatformFont, size: CGFloat, bold: Bool = false, italic: Bool = false) -> PlatformFont {
        #if os(iOS)
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: size)
        #else
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: size) ?? base
        #endif
    }

    enum Colors {
        #if os(iOS)
        static let text = UIColor.label
        static let secondary = UIColor.secondaryLabel
        static let syntax = UIColor.tertiaryLabel
        static var accent: UIColor { .tintColor }
        static let codeBackground = UIColor.tertiarySystemFill
        static var tagBackground: UIColor { UIColor.tintColor.withAlphaComponent(0.12) }
        #else
        static let text = NSColor.labelColor
        static let secondary = NSColor.secondaryLabelColor
        static let syntax = NSColor.tertiaryLabelColor
        static var accent: NSColor { .controlAccentColor }
        static let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.25)
        static var tagBackground: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.12) }
        #endif
    }
}

private extension MarkdownSpan.Kind {
    var isLineLevel: Bool {
        switch self {
        case .heading, .codeBlock, .quote: true
        default: false
        }
    }
}
