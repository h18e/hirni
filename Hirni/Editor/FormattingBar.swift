import SwiftUI
#if os(iOS)
import UIKit
#endif

/// iPhone: Leiste über der Tastatur. Während `#…` getippt wird, zeigt sie
/// passende Tags statt der Formatierungsknöpfe.
struct FormattingBar: View {
    let controller: EditorController

    var body: some View {
        Group {
            if controller.suggestions.isEmpty {
                buttons
            } else {
                TagSuggestions(controller: controller)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
        .background(.bar)
    }

    private var buttons: some View {
        HStack(spacing: 4) {
            button("Überschrift", "textformat.size", action: controller.heading)
            button("Fett", "bold", action: controller.bold)
            button("Kursiv", "italic", action: controller.italic)
            button("Liste", "list.bullet", action: controller.bulletList)
            button("Checkliste", "checklist", action: controller.checklist)
            button("Tag", "number", action: controller.insertTag)
            #if os(iOS)
            Menu {
                Button("Foto-Mediathek", systemImage: "photo.on.rectangle") { controller.attachmentRequest = .photos }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Kamera", systemImage: "camera") { controller.attachmentRequest = .camera }
                }
                Button("Datei", systemImage: "folder") { controller.attachmentRequest = .files }
                Divider()
                Button("Tabelle", systemImage: "squareshape.split.3x3") { controller.insertTable() }
                Button("Datenbank-Ansicht", systemImage: "tablecells") { controller.showsDatabasePicker = true }
            } label: {
                Label("Anhang", systemImage: "paperclip")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            #endif
            Spacer()
            #if os(iOS)
            button("Tastatur ausblenden", "keyboard.chevron.compact.down", action: controller.dismissKeyboard)
            #endif
        }
        .padding(.horizontal, 8)
    }

    private func button(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.title3)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// Die Tag-Vorschläge als antippbare Chips (iPhone-Leiste und Mac-Editor).
struct TagSuggestions: View {
    let controller: EditorController

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(controller.suggestions, id: \.self) { tag in
                    Button("#\(tag)") { controller.accept(tag) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}
