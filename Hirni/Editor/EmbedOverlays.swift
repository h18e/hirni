import HirniKit

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Zeigt eingebettete Bilder und PDFs im Editor an.
///
/// Der Text bleibt Markdown (`![](_Anhänge/foto.jpg)`). Unter dieser Zeile
/// lässt die Hervorhebung eine Lücke frei (Absatzabstand), und hier wird
/// eine Bildansicht genau in diese Lücke gelegt.
@MainActor
final class EmbedOverlays {
    static let maxImageHeight: CGFloat = 360
    static let maxPDFHeight: CGFloat = 260
    static let placeholderHeight: CGFloat = 160
    static let missingSize: CGFloat = 36
    static let gap: CGFloat = 8

    /// Pfad aus dem Text → Datei. Liefert `nil` für Web-Adressen und Pfade
    /// ausserhalb des hirni-Ordners.
    var resolve: (String) -> URL? = { _ in nil }
    var onTap: (URL) -> Void = { _ in }
    /// Eine Vorschau ist fertig geladen: Lücken neu berechnen und Bilder setzen.
    var onPreviewLoaded: () -> Void = {}

    private var views: [EmbedImageView] = []

    /// Wie viel Platz unter der Zeile mit `path` frei bleiben soll.
    func reservedHeight(for path: String, width: CGFloat) -> CGFloat {
        guard let url = resolve(path), let kind = AttachmentLinks.kind(of: path) else { return 0 }
        switch AttachmentPreviews.shared.preview(for: url) {
        case .image(_, let ratio):
            return Self.displaySize(ratio: ratio, kind: kind, width: width).height + 2 * Self.gap
        case .missing:
            return Self.missingSize + 2 * Self.gap
        case nil:
            AttachmentPreviews.shared.load(url) { [weak self] in self?.onPreviewLoaded() }
            return Self.placeholderHeight + 2 * Self.gap
        }
    }

    static func displaySize(ratio: CGFloat, kind: AttachmentLinks.Kind, width: CGFloat) -> CGSize {
        let maxHeight = kind == .pdf ? maxPDFHeight : maxImageHeight
        var size = CGSize(width: width, height: width / max(ratio, 0.01))
        if size.height > maxHeight {
            size = CGSize(width: maxHeight * ratio, height: maxHeight)
        }
        return size
    }

    /// Setzt alle Bilder an die Lücken unter ihren Zeilen.
    func layout(in textView: PlatformTextView) {
        #if os(iOS)
        let layoutManager = textView.layoutManager
        let origin = CGPoint(x: textView.textContainerInset.left, y: textView.textContainerInset.top)
        let width = textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right
        let text = textView.text ?? ""
        #else
        guard let layoutManager = textView.layoutManager else { return }
        let origin = textView.textContainerOrigin
        let width = textView.textContainer?.size.width ?? textView.bounds.width
        let text = textView.string
        #endif
        let ns = text as NSString

        var index = 0
        for span in MarkdownSyntax.spans(in: text) {
            guard case .embed(let path) = span.kind,
                  let url = resolve(path), let kind = AttachmentLinks.kind(of: path)
            else { continue }

            // Letztes Zeichen des Absatzes: Darunter liegt die Lücke.
            let paragraph = ns.paragraphRange(for: span.range)
            var last = NSMaxRange(paragraph) - 1
            if last > span.range.location, ns.character(at: last) == 0x0A { last -= 1 }
            let glyph = layoutManager.glyphIndexForCharacter(at: last)
            let line = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let top = origin.y + line.maxY + Self.gap

            let view = imageView(at: index, in: textView)
            view.url = url
            switch AttachmentPreviews.shared.preview(for: url) {
            case .image(let image, let ratio):
                let size = Self.displaySize(ratio: ratio, kind: kind, width: width)
                view.show(image, bordered: kind == .pdf)
                view.frame = CGRect(x: origin.x, y: top, width: size.width, height: size.height)
            case .missing:
                view.showMissing()
                view.frame = CGRect(x: origin.x, y: top, width: Self.missingSize, height: Self.missingSize)
            case nil:
                view.showPlaceholder()
                view.frame = CGRect(x: origin.x, y: top, width: min(width, 240), height: Self.placeholderHeight)
            }
            index += 1
        }
        while views.count > index {
            views.removeLast().removeFromSuperview()
        }
    }

    private func imageView(at index: Int, in textView: PlatformTextView) -> EmbedImageView {
        if index < views.count { return views[index] }
        let view = EmbedImageView()
        view.onTap = { [weak self] url in self?.onTap(url) }
        textView.addSubview(view)
        views.append(view)
        return view
    }
}

// MARK: - Bildansicht

#if os(iOS)
final class EmbedImageView: UIImageView {
    var url: URL?
    var onTap: ((URL) -> Void)?

    init() {
        super.init(frame: .zero)
        contentMode = .scaleAspectFit
        layer.cornerRadius = 8
        clipsToBounds = true
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        accessibilityTraits = .button
        accessibilityLabel = "Anhang öffnen"
    }

    required init?(coder: NSCoder) { fatalError("nicht verwendet") }

    @objc private func tapped() {
        if let url { onTap?(url) }
    }

    /// `bordered`: dünner Rahmen, damit eine weisse PDF-Seite sichtbar ist.
    func show(_ image: PlatformImage, bordered: Bool) {
        self.image = image
        backgroundColor = .clear
        tintColor = nil
        layer.borderWidth = bordered ? 1 : 0
        layer.borderColor = UIColor.separator.cgColor
        layer.cornerRadius = bordered ? 2 : 8
    }

    func showPlaceholder() {
        image = nil
        backgroundColor = .secondarySystemFill
    }

    func showMissing() {
        image = UIImage(systemName: "photo.badge.exclamationmark")
        tintColor = .secondaryLabel
        backgroundColor = .clear
        accessibilityLabel = "Anhang nicht gefunden"
    }
}
#else
final class EmbedImageView: NSImageView {
    var url: URL?
    var onTap: ((URL) -> Void)?

    init() {
        super.init(frame: .zero)
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        setAccessibilityLabel("Anhang öffnen")
    }

    required init?(coder: NSCoder) { fatalError("nicht verwendet") }

    override func mouseDown(with event: NSEvent) {
        if let url { onTap?(url) }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    /// `bordered`: dünner Rahmen, damit eine weisse PDF-Seite sichtbar ist.
    func show(_ image: PlatformImage, bordered: Bool) {
        self.image = image
        layer?.backgroundColor = nil
        contentTintColor = nil
        layer?.borderWidth = bordered ? 1 : 0
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.cornerRadius = bordered ? 2 : 8
    }

    func showPlaceholder() {
        image = nil
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
    }

    func showMissing() {
        image = NSImage(systemSymbolName: "photo.badge.exclamationmark", accessibilityDescription: "Anhang nicht gefunden")
        contentTintColor = .secondaryLabelColor
        layer?.backgroundColor = nil
    }
}
#endif
