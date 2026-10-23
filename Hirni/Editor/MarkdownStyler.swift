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

    static func apply(to storage: NSTextStorage) {
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
        case .link:
            storage.addAttributes([
                .foregroundColor: Colors.accent,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: range)
        case .tag:
            storage.addAttributes([
                .foregroundColor: Colors.accent,
                .backgroundColor: Colors.tagBackground,
            ], range: range)
        case .syntax:
            storage.addAttribute(.foregroundColor, value: Colors.syntax, range: range)
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
