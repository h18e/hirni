import SwiftUI

#if os(macOS)
/// Mac: Notizen in eigenständigen Fenstern. Jedes hat seinen eigenen
/// `VaultStore`, also auch eine eigene Auswahl und einen eigenen Editor.
enum NoteWindow {
    static let id = "notiz"
}

extension FocusedValues {
    /// Die Notiz im vordersten Fenster.
    @Entry var openNote: URL?
}

/// «Ablage → Notiz in neuem Fenster öffnen».
struct NoteWindowCommands: Commands {
    @FocusedValue(\.openNote) private var note
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Notiz in neuem Fenster öffnen") {
                if let note { openWindow(id: NoteWindow.id, value: note) }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(note == nil)
        }
    }
}
#endif
