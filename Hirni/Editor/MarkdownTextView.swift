import HirniKit
import SwiftUI

/// Der Markdown-Editor: eine native Textansicht (UITextView / NSTextView) mit
/// Hervorhebung, Checklisten zum Antippen und Listen-Fortsetzung bei Return.
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

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: false)
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

        controller.textView = textView
        controller.onTextChange = { [weak coordinator = context.coordinator] in coordinator?.parent.text = $0 }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate, UIGestureRecognizerDelegate {
        var parent: MarkdownTextView
        var formattingBar: UIHostingController<FormattingBar>?

        init(_ parent: MarkdownTextView) {
            self.parent = parent
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
            MarkdownStyler.apply(to: textStorage)
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView = recognizer.view as? UITextView,
                  let position = textView.closestPosition(to: recognizer.location(in: textView))
            else { return }
            let index = textView.offset(from: textView.beginningOfDocument, to: position)
            _ = parent.controller.toggleCheckbox(at: index)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}

#else

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    let controller: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CheckboxTextView(usingTextLayoutManager: false)
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
        textView.onClick = { [weak controller] index in controller?.toggleCheckbox(at: index) ?? false }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        controller.textView = textView
        controller.onTextChange = { [weak coordinator = context.coordinator] in coordinator?.parent.text = $0 }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MarkdownTextView

        init(_ parent: MarkdownTextView) {
            self.parent = parent
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
            MarkdownStyler.apply(to: textStorage)
        }
    }
}

/// NSTextView, die einen Klick auf eine Checkbox abfängt.
final class CheckboxTextView: NSTextView {
    var onClick: ((Int) -> Bool)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if onClick?(characterIndexForInsertion(at: point)) == true { return }
        super.mouseDown(with: event)
    }
}
#endif
