import HirniKit
import SwiftUI

/// Editor für eine Notiz: Titel (= Dateiname) und Markdown-Text.
///
/// Der Editor bleibt bestehen, wenn die Notiz umbenannt wird (die Adresse
/// ändert sich dabei). So kann ein Speichervorgang nie unter dem alten Namen
/// eine zweite Datei anlegen.
///
/// Vor jedem Speichern prüft er, ob die Datei inzwischen anderswo geändert
/// wurde (anderes Gerät, Finder, Claude). Dann wird zusammengeführt oder
/// nachgefragt, aber nie still überschrieben.
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
    /// Die Datei wurde anderswo geändert, und das liess sich nicht automatisch
    /// mit den Eingaben hier zusammenführen. Bis zur Entscheidung wird nicht gespeichert.
    @State private var externalChange: ExternalChange?
    @State private var showsConflictVersions = false
    @State private var loadError: String?
    @State private var controller = EditorController()
    /// Eingebettete Datenbanken (`hirni-db`-Blöcke) dieser Notiz.
    @State private var databases: EmbeddedDatabases?
    @FocusState private var titleIsFocused: Bool

    private var isLoaded: Bool { fileURL != nil }
    private var hasUnsavedChanges: Bool { text != savedText }

    struct ExternalChange: Equatable {
        let header: String?
        let text: String
        let modified: Date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let externalChange {
                ExternalChangeBanner(
                    keepMine: { Task { await keepMine(over: externalChange) } },
                    takeTheirs: { take(externalChange) },
                    keepBoth: { Task { await keepBoth(externalChange) } }
                )
            } else if let fileURL, store.hasConflict(fileURL) {
                ConflictBanner { showsConflictVersions = true }
            }

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
        .overlay { loadingOverlay }
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
        .sheet(item: editingEmbeddedRow) { row in
            RowFormView(document: row.document, rowID: row.rowID) { id in
                databases?.editingRow = nil
                Task {
                    if let page = await row.document.page(for: id) { store.selectedNote = page }
                }
            }
        }
        .sheet(isPresented: showsDatabasePicker) {
            DatabasePicker(note: fileURL ?? url) { controller.insertBlock($0) }
        }
        .sheet(isPresented: $showsConflictVersions) {
            if let fileURL {
                ConflictResolverView(url: fileURL, currentText: Frontmatter.join(header: header, body: text))
            }
        }
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
            Task {
                await reloadIfChangedElsewhere()
                await databases?.refresh()
            }
        }
        .onDisappear {
            if let databases { Task { await databases.closeAll() } }
            if store.openEditor?.url == fileURL { store.openEditor = nil }
            // Ungelöste Fremdänderung: lieber nicht speichern als überschreiben.
            guard externalChange == nil else { return }
            let snapshot = Frontmatter.join(header: header, body: text)
            if let fileURL, text != savedText {
                Task { [store] in _ = await store.write(snapshot, to: fileURL) }
            }
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if let loadError {
            ContentUnavailableView(
                "Notiz lässt sich nicht öffnen",
                systemImage: "exclamationmark.triangle",
                description: Text(loadError)
            )
            .background(.background)
        } else if !isLoaded {
            if let progress = store.downloadProgress(of: url) {
                ProgressView(value: progress) {
                    Text("Wird aus iCloud geladen … \(Int(progress * 100)) %")
                }
                .frame(maxWidth: 240)
            } else {
                ProgressView("Wird geladen …")
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
            Button("Datenbank", systemImage: "tablecells") { controller.showsDatabasePicker = true }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .help("Datenbank-Ansicht einfügen (⇧⌘D)")
        }
    }
    #endif

    // MARK: - Laden und Speichern

    /// Öffnet `newURL`. Nach einem Umbenennen ist das bereits die offene Datei,
    /// dann passiert nichts.
    private func open(_ newURL: URL) async {
        guard newURL != fileURL else { return }
        await save()
        await databases?.closeAll()
        externalChange = nil
        loadError = nil

        let content: String
        switch await store.readForEditor(newURL) {
        case .success(let text):
            content = text
        case .failure:
            loadError = "Die Datei ist keine lesbare Textdatei (UTF-8). hirni verändert sie nicht."
            return
        }
        let modified = await store.modificationDate(of: newURL) ?? .now
        let (header, body) = Frontmatter.split(content)
        // Zuerst anmelden: Die Hervorhebung braucht den Ordner der Notiz,
        // um eingebettete Bilder zu finden.
        register(for: newURL)
        self.header = header
        show(body)
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

    /// Setzt Text als neuen gespeicherten Stand (Laden, Fremdänderung übernehmen).
    private func show(_ body: String) {
        text = body
        controller.setText(body)
        savedText = body
    }

    private func save() async {
        guard let fileURL, !isRenaming, hasUnsavedChanges, externalChange == nil else { return }
        var snapshot = text

        // Wurde die Datei seit dem letzten Laden/Speichern anderswo geändert?
        if let diskModified = await store.modificationDate(of: fileURL),
           diskModified.timeIntervalSince(savedModified) > 0.5,
           case .success(let disk) = await store.readForEditor(fileURL) {
            let (diskHeader, theirs) = Frontmatter.split(disk)
            header = diskHeader
            if theirs != savedText {
                guard let merged = ThreeWayMerge.merge(base: savedText, mine: snapshot, theirs: theirs) else {
                    externalChange = ExternalChange(header: diskHeader, text: theirs, modified: diskModified)
                    return
                }
                // Beides passt zusammen: den zusammengeführten Text zeigen und speichern.
                if merged != snapshot {
                    text = merged
                    controller.setText(merged)
                }
                snapshot = merged
            }
        }

        if let modified = await store.write(Frontmatter.join(header: header, body: snapshot), to: fileURL) {
            savedText = snapshot
            savedModified = modified
        }
    }

    /// Hat ein anderes Gerät, der Finder oder Claude die Datei geändert, wird der
    /// neue Stand übernommen. Gibt es hier ungespeicherte Eingaben, wird über
    /// `save()` zusammengeführt.
    private func reloadIfChangedElsewhere() async {
        guard let fileURL, !isRenaming, externalChange == nil,
              let modified = await store.modificationDate(of: fileURL),
              modified.timeIntervalSince(savedModified) > 0.5
        else { return }
        if hasUnsavedChanges {
            await save()
            return
        }
        guard case .success(let content) = await store.readForEditor(fileURL),
              !hasUnsavedChanges, fileURL == self.fileURL
        else { return }
        let (header, body) = Frontmatter.split(content)
        self.header = header
        show(body)
        savedModified = modified
    }

    /// Nach dem Lösen eines iCloud-Konflikts: den Stand der Datei zeigen.
    private func reloadFromDisk() async {
        guard let fileURL, case .success(let content) = await store.readForEditor(fileURL) else { return }
        let (header, body) = Frontmatter.split(content)
        self.header = header
        show(body)
        savedModified = await store.modificationDate(of: fileURL) ?? .now
    }

    // MARK: - Fremdänderung entscheiden

    private func keepMine(over change: ExternalChange) async {
        externalChange = nil
        savedModified = change.modified // jetzt bewusst überschreiben
        await save()
    }

    private func take(_ change: ExternalChange) {
        externalChange = nil
        header = change.header
        show(change.text)
        savedModified = change.modified
    }

    private func keepBoth(_ change: ExternalChange) async {
        guard let fileURL else { return }
        let mine = Frontmatter.join(header: header, body: text)
        if await store.saveConflictCopy(text: mine, of: fileURL) != nil {
            take(change)
        }
    }

    // MARK: - Titel

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
            // Als Zeilen-Seite in einer Datenbank geöffnet, bleibt die Datenbank gewählt.
            if store.selectedNote == fileURL { store.selectedNote = newURL }
            register(for: newURL)
        }
        title = Vault.title(of: self.fileURL ?? fileURL)
        isRenaming = false
        // Was während des Umbenennens getippt wurde, jetzt unter dem neuen Namen sichern.
        await save()
    }

    /// Meldet sich beim Store, damit er vor Dateioperationen speichern kann,
    /// und sagt dem Editor, wo die Anhänge dieser Notiz liegen.
    private func register(for fileURL: URL) {
        let vault = store.vault
        controller.overlays.resolve = { vault.resolveAttachment($0, for: fileURL) }
        controller.onFileDrop = { urls in Task { await importFiles(urls) } }
        connectDatabases(for: fileURL)
        store.openEditor = EditorHandle(
            url: fileURL,
            flush: { await save() },
            reloadHeader: { await reloadHeader() },
            reloadFromDisk: { await reloadFromDisk() }
        )
    }

    // MARK: - Eingebettete Datenbanken

    private func connectDatabases(for fileURL: URL) {
        let databases = self.databases ?? EmbeddedDatabases(store: store)
        self.databases = databases
        databases.note = fileURL
        let overlays = controller.overlays
        databases.onLayoutChange = { [weak overlays] in overlays?.onPreviewLoaded() }
        overlays.databaseHeight = { [weak databases] in databases?.height(for: $0) ?? 0 }
        overlays.makeDatabaseView = { [weak databases, store] embed in
            guard let databases else { return AnyView(EmptyView()) }
            return AnyView(EmbeddedDatabaseView(embed: embed, registry: databases).environment(store))
        }
    }

    private var editingEmbeddedRow: Binding<EmbeddedDatabases.EditingRow?> {
        Binding(get: { databases?.editingRow }, set: { databases?.editingRow = $0 })
    }

    private var showsDatabasePicker: Binding<Bool> {
        Binding(get: { controller.showsDatabasePicker }, set: { controller.showsDatabasePicker = $0 })
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
        guard let fileURL, case .success(let content) = await store.readForEditor(fileURL) else { return }
        header = Frontmatter.split(content).header
    }
}
