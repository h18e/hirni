import HirniKit
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
        HStack(spacing: 2) {
            button("Überschrift", "textformat.size", action: controller.heading)
            button("Fett", "bold", action: controller.bold)
            button("Kursiv", "italic", action: controller.italic)
            FormatMenu(controller: controller)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 38, height: 44)
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
                Button("Link auf Notiz", systemImage: "link") { controller.showsNotePicker = true }
                Button("Tabelle", systemImage: "squareshape.split.3x3") { controller.insertTable() }
                Button("Spalten", systemImage: "rectangle.split.2x1") { controller.insertColumns() }
                Button("Datenbank-Ansicht", systemImage: "tablecells") { controller.showsDatabasePicker = true }
            } label: {
                Label("Anhang", systemImage: "paperclip")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 38, height: 44)
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
            .frame(width: 38, height: 44)
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

/// Weitere Formate: unterstrichen, durchgestrichen, markiert, Textfarbe.
struct FormatMenu: View {
    let controller: EditorController

    var body: some View {
        Menu("Format", systemImage: "paintpalette") {
            Button("Unterstrichen", systemImage: "underline", action: controller.underline)
            Button("Durchgestrichen", systemImage: "strikethrough", action: controller.strikethrough)
            Button("Markieren", systemImage: "highlighter", action: controller.highlight)
            Section("Textfarbe") {
                ForEach(TextColor.allCases, id: \.self) { color in
                    Button(color.label) { controller.setColor(color) }
                }
                Button("Farbe entfernen", systemImage: "xmark.circle") { controller.setColor(nil) }
            }
        }
    }
}
