import HirniKit
import SwiftUI

/// Einfacher Editor für Etappe 1: Titel (= Dateiname) und Text.
/// Markdown-Hervorhebung und Formatierungsleiste folgen in Etappe 3.
///
/// Der Editor bleibt bestehen, wenn die Notiz umbenannt wird (die Adresse
/// ändert sich dabei). So kann ein Speichervorgang nie unter dem alten Namen
/// eine zweite Datei anlegen.
struct NoteEditorView: View {
    @Environment(VaultStore.self) private var store
    /// Die in der Liste ausgewählte Notiz.
    let url: URL

    /// Die Datei, die dieser Editor gerade bearbeitet.
    @State private var fileURL: URL?
    @State private var title = ""
    @State private var text = ""
    /// Stand der Datei auf der Festplatte. Weicht `text` davon ab, gibt es
    /// ungespeicherte Änderungen.
    @State private var savedText = ""
    @State private var savedModified: Date = .distantPast
    @State private var isRenaming = false
    @FocusState private var titleIsFocused: Bool

    private var isLoaded: Bool { fileURL != nil }
    private var hasUnsavedChanges: Bool { text != savedText }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(Vault.title(of: fileURL ?? url), text: $title)
                .font(.title.bold())
                .textFieldStyle(.plain)
                .focused($titleIsFocused)
                .onSubmit { Task { await commitTitle() } }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 15)
        }
        .disabled(!isLoaded)
        .overlay {
            if !isLoaded { ProgressView("Wird geladen …") }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: url) { await open(url) }
        // Automatisch speichern, 1 Sekunde nach der letzten Eingabe.
        .task(id: text) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await save()
        }
        .onChange(of: titleIsFocused) { _, focused in
            if !focused { Task { await commitTitle() } }
        }
        .onChange(of: store.revision) {
            Task { await reloadIfChangedElsewhere() }
        }
        .onDisappear {
            let snapshot = text
            if let fileURL, snapshot != savedText {
                Task { [store] in _ = await store.write(snapshot, to: fileURL) }
            }
        }
    }

    /// Öffnet `newURL`. Nach einem Umbenennen ist das bereits die offene Datei,
    /// dann passiert nichts.
    private func open(_ newURL: URL) async {
        guard newURL != fileURL else { return }
        await save()

        guard let content = await store.read(newURL) else { return }
        let modified = await store.modificationDate(of: newURL) ?? .now
        text = content
        savedText = content
        savedModified = modified
        title = Vault.title(of: newURL)
        fileURL = newURL

        if store.justCreatedNote == newURL {
            store.justCreatedNote = nil
            title = "" // der Platzhalter «Neue Notiz» bleibt sichtbar
            // Erst nach dem nächsten Bildaufbau: Vorher ist das Feld noch deaktiviert.
            try? await Task.sleep(for: .milliseconds(50))
            titleIsFocused = true
        }
    }

    private func save() async {
        guard let fileURL, !isRenaming, hasUnsavedChanges else { return }
        let snapshot = text
        if let modified = await store.write(snapshot, to: fileURL) {
            savedText = snapshot
            savedModified = modified
        }
    }

    private func commitTitle() async {
        guard let fileURL, !isRenaming else { return }
        let newTitle = title.trimmingCharacters(in: .whitespaces)
        guard !newTitle.isEmpty, newTitle != Vault.title(of: fileURL) else {
            title = Vault.title(of: fileURL)
            return
        }

        await save()
        isRenaming = true
        let newURL = await store.renameNote(fileURL, to: newTitle)
        if let newURL {
            self.fileURL = newURL
            savedModified = await store.modificationDate(of: newURL) ?? savedModified
            store.selectedNote = newURL
        }
        title = Vault.title(of: self.fileURL ?? fileURL)
        isRenaming = false
        // Was während des Umbenennens getippt wurde, jetzt unter dem neuen Namen sichern.
        await save()
    }

    /// Hat ein anderes Gerät, der Finder oder Claude die Datei geändert, und
    /// gibt es hier keine ungespeicherten Eingaben, wird der neue Stand übernommen.
    /// (Echte Konflikte – beide Seiten geändert – behandelt Etappe 6.)
    private func reloadIfChangedElsewhere() async {
        guard let fileURL, !isRenaming, !hasUnsavedChanges,
              let modified = await store.modificationDate(of: fileURL),
              modified.timeIntervalSince(savedModified) > 0.5,
              let content = await store.read(fileURL),
              !hasUnsavedChanges, fileURL == self.fileURL
        else { return }
        text = content
        savedText = content
        savedModified = modified
    }
}
