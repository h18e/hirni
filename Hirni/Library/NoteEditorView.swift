import HirniKit
import SwiftUI

/// Editor für eine Notiz: Titel (= Dateiname) und Markdown-Text.
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
    /// YAML-Kopf (z. B. `angepinnt: true`). Er wird im Editor nicht angezeigt,
    /// aber beim Speichern wieder vor den Text gesetzt.
    @State private var header: String?
    @State private var text = ""
    /// Stand der Datei auf der Festplatte. Weicht `text` davon ab, gibt es
    /// ungespeicherte Änderungen.
    @State private var savedText = ""
    @State private var savedModified: Date = .distantPast
    @State private var isRenaming = false
    @State private var controller = EditorController()
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

            MarkdownTextView(text: $text, controller: controller)
            #if os(macOS)
            if !controller.suggestions.isEmpty {
                TagSuggestions(controller: controller)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
            #endif
        }
        .disabled(!isLoaded)
        .overlay {
            if !isLoaded { ProgressView("Wird geladen …") }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .toolbar { formattingToolbar }
        #endif
        .modifier(AttachmentPickers(
            controller: controller,
            importFiles: { await importFiles($0) },
            importPhoto: { await importPhoto($0) }
        ))
        .task(id: url) { await open(url) }
        .task { await store.refreshTags() }
        .onChange(of: store.tags, initial: true) { _, tags in
            controller.knownTags = tags
        }
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
            if store.openEditor?.url == fileURL { store.openEditor = nil }
            let snapshot = Frontmatter.join(header: header, body: text)
            if let fileURL, text != savedText {
                Task { [store] in _ = await store.write(snapshot, to: fileURL) }
            }
        }
    }

    #if os(macOS)
    /// Formatieren am Mac: Knöpfe in der Fensterleiste, mit Tastenkürzeln.
    @ToolbarContentBuilder
    private var formattingToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Überschrift", systemImage: "textformat.size", action: controller.heading)
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .help("Überschrift (⇧⌘H)")
            Button("Fett", systemImage: "bold", action: controller.bold)
                .keyboardShortcut("b")
                .help("Fett (⌘B)")
            Button("Kursiv", systemImage: "italic", action: controller.italic)
                .keyboardShortcut("i")
                .help("Kursiv (⌘I)")
            Button("Liste", systemImage: "list.bullet", action: controller.bulletList)
                .keyboardShortcut("8", modifiers: [.command, .shift])
                .help("Liste (⇧⌘8)")
            Button("Checkliste", systemImage: "checklist", action: controller.checklist)
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .help("Checkliste (⇧⌘L)")
            Button("Anhang", systemImage: "paperclip") { controller.attachmentRequest = .files }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .help("Bild oder PDF einfügen (⇧⌘A) – oder Datei in den Text ziehen")
        }
    }
    #endif

    /// Öffnet `newURL`. Nach einem Umbenennen ist das bereits die offene Datei,
    /// dann passiert nichts.
    private func open(_ newURL: URL) async {
        guard newURL != fileURL else { return }
        await save()

        guard let content = await store.read(newURL) else { return }
        let modified = await store.modificationDate(of: newURL) ?? .now
        let (header, body) = Frontmatter.split(content)
        // Zuerst anmelden: Die Hervorhebung braucht den Ordner der Notiz,
        // um eingebettete Bilder zu finden.
        register(for: newURL)
        self.header = header
        text = body
        controller.setText(body)
        savedText = body
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
        if let modified = await store.write(Frontmatter.join(header: header, body: snapshot), to: fileURL) {
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
            register(for: newURL)
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
        let (header, body) = Frontmatter.split(content)
        self.header = header
        text = body
        controller.setText(body)
        savedText = body
        savedModified = modified
    }

    /// Meldet sich beim Store, damit er vor Dateioperationen speichern kann,
    /// und sagt dem Editor, wo die Anhänge dieser Notiz liegen.
    private func register(for fileURL: URL) {
        let vault = store.vault
        controller.overlays.resolve = { vault.resolveAttachment($0, for: fileURL) }
        controller.onFileDrop = { urls in Task { await importFiles(urls) } }
        store.openEditor = EditorHandle(
            url: fileURL,
            flush: { await save() },
            reloadHeader: { await reloadHeader() }
        )
    }

    // MARK: - Anhänge

    private func importFiles(_ urls: [URL]) async {
        guard let fileURL else { return }
        for url in urls {
            if let markdown = await store.importAttachment(copying: url, for: fileURL) {
                controller.insertBlock(markdown)
            }
        }
    }

    /// Fotos aus Mediathek oder Kamera: als JPEG, höchstens 3000 Pixel.
    private func importPhoto(_ data: Data) async {
        guard let fileURL else { return }
        let jpeg = ImageEncoding.jpeg(from: data) ?? data
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "Foto-" + formatter.string(from: .now)
        if let markdown = await store.importAttachment(data: jpeg, fileExtension: "jpg", baseName: name, for: fileURL) {
            controller.insertBlock(markdown)
        }
    }

    /// Liest nur den YAML-Kopf neu (nach Anpinnen), der Text bleibt unberührt.
    private func reloadHeader() async {
        guard let fileURL, let content = await store.read(fileURL) else { return }
        header = Frontmatter.split(content).header
    }
}
