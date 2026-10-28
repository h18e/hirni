#if os(iOS)
import SwiftUI
import UIKit

/// iPhone: Titelfeld als UITextField.
///
/// SwiftUIs `@FocusState` setzt den Fokus nicht, wenn SwiftUI den Editor
/// fälschlich als «verschwunden» führt (passiert beim Öffnen einer neuen
/// Notiz). UIKit kennt das Problem nicht: `becomeFirstResponder` klappt immer.
struct TitleField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    /// Jede Erhöhung setzt den Cursor ins Feld.
    let focusRequest: Int
    /// Fokus verloren: Titel übernehmen.
    let onEndEditing: () -> Void
    /// Return: Titel übernehmen und weiter in den Text.
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        let base = UIFont.preferredFont(forTextStyle: .title1)
        field.font = UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor, size: 0)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .next
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultHigh, for: .vertical)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text, !field.isFirstResponder { field.text = text }
        if field.placeholder != placeholder { field.placeholder = placeholder }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { field.becomeFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TitleField
        var focusRequest: Int

        init(_ parent: TitleField) {
            self.parent = parent
            focusRequest = parent.focusRequest
        }

        @objc func changed(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onEndEditing()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}
#endif
