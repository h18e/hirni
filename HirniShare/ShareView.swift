import HirniKit
import SwiftUI
import UniformTypeIdentifiers

/// Liest, was geteilt wurde, und legt daraus eine Notiz in der Inbox an.
@Observable
final class ShareModel {
    nonisolated static let containerIdentifier = "iCloud.ch.hebera.hirni"

    private let context: NSExtensionContext?
    var title = ""
    var text = ""
    /// Bilder und PDFs, als Kopien im temporären Ordner.
    var files: [URL] = []
    var isLoading = true
    var isSaving = false
    var error: String?
    /// Geteilte Webseite (http/https).
    private(set) var pageURL: URL?
    /// «Ganze Seite» statt nur des Links; die Wahl bleibt gespeichert.
    var importsPage = UserDefaults.standard.bool(forKey: "ganzeSeite") {
        didSet {
            UserDefaults.standard.set(importsPage, forKey: "ganzeSeite")
            if importsPage { Task { await loadPage() } }
        }
    }
    private(set) var pageText: String?
    private(set) var isLoadingPage = false
    private var suggestedTitle = ""

    init(context: NSExtensionContext?) {
        self.context = context
        Task { await load() }
    }

    private func load() async {
        let items = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        var texts: [String] = []
        var firstURL: URL?
        var suggestedTitle = items.compactMap { $0.attributedTitle?.string }.first { !$0.isEmpty }
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
                   let file = await copy(provider, type: .pdf) {
                    files.append(file)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                          let file = await copy(provider, type: .image) {
                    files.append(file)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let url = await loadURL(provider), !url.isFileURL {
                    firstURL = firstURL ?? url
                    texts.append(url.absoluteString)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let string = await loadText(provider) {
                    texts.append(string)
                }
            }
            // Safari & Co. schicken oft den Seitentitel als Text mit.
            if let content = item.attributedContentText?.string, !content.isEmpty, !texts.contains(content) {
                if suggestedTitle == nil, firstURL != nil { suggestedTitle = content } else { texts.insert(content, at: 0) }
            }
        }
        text = texts.joined(separator: "\n\n")
        title = suggestedTitle ?? SharedItem.suggestedTitle(text: text, url: firstURL)
        self.suggestedTitle = title
        if text.isEmpty, files.isEmpty { error = "Hirni kann mit diesem Inhalt nichts anfangen." }
        if let firstURL, ["http", "https"].contains(firstURL.scheme?.lowercased()) { pageURL = firstURL }
        isLoading = false
        if importsPage { await loadPage() }
    }

    /// Holt den Inhalt der Seite (einmal).
    private func loadPage() async {
        guard let pageURL, pageText == nil, !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        do {
            let page = try await WebPageLoader.load(pageURL)
            guard !page.markdown.isEmpty else {
                error = "Auf der Seite wurde kein Text gefunden."
                return
            }
            pageText = page.markdown
            error = nil
            if title == suggestedTitle, !page.title.isEmpty { title = page.title }
        } catch {
            self.error = "Die Seite liess sich nicht laden. Gesichert wird nur der Link."
        }
    }

    /// Was in die Notiz kommt: der Link, bei «Ganze Seite» darunter der Inhalt.
    var noteText: String {
        guard importsPage, let pageText, let pageURL else { return text }
        return "Quelle: " + pageURL.absoluteString + "\n\n" + pageText
    }

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { string, _ in continuation.resume(returning: string) }
        }
    }

    /// Die Datei gilt nur während des Rückrufs, darum gleich kopieren.
    private func copy(_ provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { return continuation.resume(returning: nil) }
                let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                let target = folder.appending(path: url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: target)
                    continuation.resume(returning: target)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func save() async {
        isSaving = true
        let item = SharedItem(title: title, text: noteText)
        let files = files
        let result: String? = await Task.detached {
            do {
                // Direkt in die Inbox in iCloud Drive; geht das nicht, in die
                // Warteschlange, die Hirni beim nächsten Start abholt.
                if let container = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier) {
                    let root = container.appending(path: "Documents", directoryHint: .isDirectory)
                    try VaultLayout.prepare(root: root)
                    try Vault(root: root).importShared(item, files: files)
                } else if let group = AppGroup.folder {
                    try SharedInbox.enqueue(item, files: files, in: group.appending(path: SharedInbox.queueFolderName, directoryHint: .isDirectory))
                } else {
                    return "Weder iCloud Drive noch der gemeinsame Ordner sind erreichbar."
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        isSaving = false
        if let result {
            error = result
        } else {
            context?.completeRequest(returningItems: nil)
        }
    }

    func cancel() {
        context?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}

/// Das Blatt im Teilen-Menü: Titel, Vorschau, «In Hirni sichern».
///
/// Am Mac zeigt eine Erweiterung keine Symbolleiste, darum stehen die
/// Knöpfe dort unten im Blatt.
struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        #if os(iOS)
        NavigationStack {
            form
                .navigationTitle("In Hirni sichern")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { cancelButton }
                    ToolbarItem(placement: .confirmationAction) { saveButton }
                }
        }
        #else
        VStack(spacing: 0) {
            Text("In Hirni sichern")
                .font(.headline)
                .padding(.top, 14)
            form
            HStack {
                Spacer()
                cancelButton
                    .keyboardShortcut(.cancelAction)
                saveButton
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 420, height: 380)
        #endif
    }

    private var form: some View {
        Form {
            if model.isLoading {
                ProgressView()
            } else {
                Section("Titel") {
                    TextField("Titel", text: $model.title)
                        .labelsHidden()
                }
                if model.pageURL != nil {
                    Section {
                        Picker("Übernehmen", selection: $model.importsPage) {
                            Text("Link").tag(false)
                            Text("Ganze Seite").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    } footer: {
                        Text("«Ganze Seite» übernimmt den Text der Seite mit Überschriften, Listen und Tabellen, ohne Bilder und Menüs.")
                    }
                }
                if model.importsPage && model.isLoadingPage {
                    Section("Text") {
                        ProgressView("Seite wird geladen …")
                    }
                } else if !model.noteText.isEmpty {
                    Section("Text") {
                        Text(model.noteText)
                            .lineLimit(model.importsPage ? 10 : 5)
                            .foregroundStyle(.secondary)
                    }
                }
                if !model.files.isEmpty {
                    Section("Anhänge") {
                        ForEach(model.files, id: \.self) { file in
                            Label(file.lastPathComponent, systemImage: file.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "photo")
                                .lineLimit(1)
                        }
                    }
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var cancelButton: some View {
        Button("Abbrechen") { model.cancel() }
    }

    private var saveButton: some View {
        Button("Sichern") { Task { await model.save() } }
            .disabled(model.isLoading || model.isSaving || model.isLoadingPage || (model.text.isEmpty && model.files.isEmpty))
    }
}
