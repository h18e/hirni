import HirniKit
import SwiftUI

/// Der Markdown-Editor: eine native Textansicht (UITextView / NSTextView) mit
/// Hervorhebung, Checklisten zum Antippen, Listen-Fortsetzung bei Return und
/// eingeblendeten Bildern.
///
/// Text fliesst nur hinaus (Bindung `text`). Neuer Text von aussen kommt über
/// `EditorController.setText`, siehe dort.
///
/// Bewusst TextKit 1: Die Hervorhebung ändert bei jeder Eingabe die Attribute
/// des ganzen Texts, und das ist mit TextKit 1 erprobt und berechenbar.
#if os(iOS)
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    let controller: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> EditorTextView {
        let textView = EditorTextView(usingTextLayoutManager: false)
        textView.font = MarkdownStyler.bodyFont
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 20, bottom: 60, right: 20)
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        // Markdown braucht gerade Anführungszeichen und echte Bindestriche.
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.delegate = context.coordinator
        textView.textStorage.delegate = context.coordinator
        textView.layoutManager.delegate = context.coordinator
        textView.onWidthChange = { [weak coordinator = context.coordinator] in coordinator?.restyle() }

        let bar = UIHostingController(rootView: FormattingBar(controller: controller))
        bar.view.frame = CGRect(x: 0, y: 0, width: 0, height: 48)
        bar.view.autoresizingMask = [.flexibleWidth]
        bar.view.backgroundColor = .clear
        bar.sizingOptions = []
        textView.inputAccessoryView = bar.view
        context.coordinator.formattingBar = bar

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        textView.addGestureRecognizer(tap)

        context.coordinator.connect(textView)
        return textView
    }

    func updateUIView(_ textView: EditorTextView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate, NSLayoutManagerDelegate,
        UIGestureRecognizerDelegate {
        var parent: MarkdownTextView
        var formattingBar: UIHostingController<FormattingBar>?
        private weak var textView: EditorTextView?
        private var layoutScheduled = false

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func connect(_ textView: EditorTextView) {
            self.textView = textView
            let controller = parent.controller
            controller.overlays.onPreviewLoaded = { [weak self] in self?.restyle() }
            controller.textView = textView
            controller.onTextChange = { [weak self] in self?.parent.text = $0 }
        }

        /// Hervorhebung neu berechnen, ohne den Text zu ändern (z. B. wenn ein
        /// Bild fertig geladen ist und seine Lücke die richtige Höhe bekommt).
        func restyle() {
            guard let textView else { return }
            style(textView.textStorage)
        }

        private func style(_ storage: NSTextStorage) {
            guard let textView else { return }
            let width = textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right
            let overlays = parent.controller.overlays
            MarkdownStyler.apply(
                to: storage,
                reservedHeight: { overlays.reservedHeight(for: $0, width: width) },
                databaseHeight: overlays.databaseHeight
            )
            scheduleLayout()
        }

        private func scheduleLayout() {
            guard !layoutScheduled else { return }
            layoutScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let textView = self.textView else { return }
                self.layoutScheduled = false
                self.parent.controller.overlays.layout(in: textView)
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.controller.updateSuggestions()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.controller.updateSuggestions()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n", parent.controller.handleReturn() { return false }
            return true
        }

        func textStorage(
            _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            style(textStorage)
        }

        func layoutManager(
            _ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd: Bool
        ) {
            scheduleLayout()
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView = recognizer.view as? UITextView,
                  let position = textView.closestPosition(to: recognizer.location(in: textView))
            else { return }
            let index = textView.offset(from: textView.beginningOfDocument, to: position)
            if parent.controller.toggleCheckbox(at: index) { return }
            // Ein Tipp auf einen Link öffnet ihn (wie in Apple Notizen). Die
            // Stelle liegt zwischen zwei Zeichen, darum beide prüfen, und nur,
            // wenn der Finger wirklich auf dem Zeichen liegt (nicht daneben).
            let point = recognizer.location(in: textView)
            for candidate in [index, index - 1] {
                if let url = parent.controller.link(at: candidate), rect(ofCharacterAt: candidate, in: textView).contains(point) {
                    UIApplication.shared.open(url)
                    return
                }
            }
        }

        private func rect(ofCharacterAt index: Int, in textView: UITextView) -> CGRect {
            guard index >= 0, index < textView.textStorage.length else { return .null }
            let layoutManager = textView.layoutManager
            let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            return layoutManager.boundingRect(forGlyphRange: glyphs, in: textView.textContainer)
                .offsetBy(dx: textView.textContainerInset.left, dy: textView.textContainerInset.top)
                .insetBy(dx: -3, dy: -3)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}

/// UITextView, die meldet, wenn sich ihre Breite ändert (Drehen, Split View):
/// Dann müssen die Bildgrössen neu berechnet werden.
final class EditorTextView: UITextView {
    var onWidthChange: (() -> Void)?
    private var lastWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastWidth {
            lastWidth = bounds.width
            onWidthChange?()
        }
    }
}

#else

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    let controller: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = EditorTextView(usingTextLayoutManager: false)
        textView.font = MarkdownStyler.bodyFont
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 16, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.layoutManager?.delegate = context.coordinator
        textView.onClick = { [weak controller] index in controller?.toggleCheckbox(at: index) ?? false }
        textView.onFileDrop = { [weak controller] urls in controller?.onFileDrop?(urls) }
        textView.onWidthChange = { [weak coordinator = context.coordinator] in coordinator?.restyle() }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        context.coordinator.connect(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate, NSLayoutManagerDelegate {
        var parent: MarkdownTextView
        private weak var textView: EditorTextView?
        private var layoutScheduled = false

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func connect(_ textView: EditorTextView) {
            self.textView = textView
            let controller = parent.controller
            controller.overlays.onPreviewLoaded = { [weak self] in self?.restyle() }
            controller.textView = textView
            controller.onTextChange = { [weak self] in self?.parent.text = $0 }
        }

        func restyle() {
            guard let storage = textView?.textStorage else { return }
            style(storage)
        }

        private func style(_ storage: NSTextStorage) {
            guard let textView else { return }
            let width = textView.textContainer?.size.width ?? textView.bounds.width
            let overlays = parent.controller.overlays
            MarkdownStyler.apply(
                to: storage,
                reservedHeight: { overlays.reservedHeight(for: $0, width: width) },
                databaseHeight: overlays.databaseHeight
            )
            scheduleLayout()
        }

        private func scheduleLayout() {
            guard !layoutScheduled else { return }
            layoutScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let textView = self.textView else { return }
                self.layoutScheduled = false
                self.parent.controller.overlays.layout(in: textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.controller.updateSuggestions()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.controller.updateSuggestions()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                return parent.controller.handleReturn()
            case #selector(NSResponder.insertTab(_:)):
                // Tab übernimmt den ersten Tag-Vorschlag.
                guard let first = parent.controller.suggestions.first else { return false }
                parent.controller.accept(first)
                return true
            default:
                return false
            }
        }

        func textStorage(
            _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            style(textStorage)
        }

        func layoutManager(
            _ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd: Bool
        ) {
            scheduleLayout()
        }
    }
}

/// NSTextView mit drei Zusätzen: Klick auf eine Checkbox, Bilder und PDFs
/// per Drag'n'Drop als Anhang, Meldung bei Breitenänderung.
final class EditorTextView: NSTextView {
    var onClick: ((Int) -> Bool)?
    var onFileDrop: (([URL]) -> Void)?
    var onWidthChange: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if onClick?(characterIndexForInsertion(at: point)) == true { return }
        super.mouseDown(with: event)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = (sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []).filter { AttachmentLinks.kind(of: $0.lastPathComponent) != nil }
        guard !urls.isEmpty, let onFileDrop else { return super.performDragOperation(sender) }
        // Einfügen dort, wo losgelassen wurde.
        let point = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        onFileDrop(urls)
        return true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { onWidthChange?() }
    }
}
#endif
