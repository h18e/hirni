import Foundation
import HirniKit
import Observation
#if os(iOS)
import UIKit
#endif
import os

let vaultLog = Logger(subsystem: "ch.hebera.hirni", category: "vault")

/// Was in der Seitenleiste ausgewählt ist.
enum SidebarItem: Hashable {
    case inbox
    case folder(URL)
    case tag(String)
    /// Alle Checkboxen aus allen Notizen.
    case tasks
    case trash
    /// Hilfe: alle Funktionen und Platzhalter erklärt.
    case help
}

/// Ein Tag mit der Anzahl Notizen, für die Seitenleiste.
struct TagCount: Identifiable, Hashable {
    let name: String
    let count: Int
    var id: String { name.lowercased() }
}

/// Zentraler Zustand der App: Ordnerbaum, Notizliste, Auswahl.
///
/// Alle Dateioperationen laufen über `HirniKit.Vault` in einem Hintergrund-Task.
/// Danach wird neu eingelesen. Änderungen von anderen Geräten oder Programmen
/// meldet der `VaultMonitor`, der dann ebenfalls `reload()` auslöst.
@Observable
final class VaultStore {
    let vault: Vault

    private(set) var folders: [FolderNode] = []
    private(set) var notes: [NoteSummary] = []
    /// Reihenfolge der Notizliste, für alle Ordner gleich; bleibt gespeichert.
    var noteSort = VaultStore.savedNoteSort() {
        didSet {
            guard oldValue != noteSort else { return }
            notes = noteSort.apply(notes)
            UserDefaults.standard.set(noteSort.field.rawValue, forKey: Self.sortFieldKey)
            UserDefaults.standard.set(noteSort.ascending, forKey: Self.sortAscendingKey)
        }
    }
    private(set) var trash: [TrashEntry] = []
    /// Alle Pendenzen (Checkboxen) aus allen Notizen.
    private(set) var tasks: [TaskItem] = []
    /// Stichtage der Pendenzen (aus `_Hirni/Pendenzen.json`).
    private(set) var dueDates = TaskDueDates()
    /// Vorlagen aus dem Ordner «Vorlagen».
    private(set) var templates: [NoteTemplate] = []
    /// Alle Tags im hirni-Ordner, die häufigsten zuerst (für Vorschläge).
    private(set) var tags: [String] = []
    /// Dieselben Tags mit Anzahl Notizen (für die Seitenleiste).
    private(set) var tagCounts: [TagCount] = []
    /// Konflikte und laufende Downloads, gemeldet von iCloud.
    private(set) var iCloudStatus = VaultMonitor.Status()

    var sidebarSelection: SidebarItem? = .inbox {
        didSet {
            guard oldValue != sidebarSelection else { return }
            #if os(macOS)
            // Offene Tabs bleiben beim Wechsel des Ordners sichtbar.
            if tabs.urls.count < 2 { selectedNote = nil }
            #else
            selectedNote = nil
            #endif
            // Gemerkte Liste sofort zeigen, die frische folgt.
            notes = currentFolderURL.flatMap { snapshot?.notes(in: $0, vault: vault) }.map(noteSort.apply) ?? []
            Task { await reload() }
        }
    }
    var selectedNote: URL? {
        didSet {
            if let selectedNote {
                if addingTab {
                    addingTab = false
                    tabs.openNew(selectedNote)
                } else {
                    tabs.show(selectedNote)
                }
            }
            // Wegnavigieren speichert den offenen Editor. Darauf, dass SwiftUI
            // beim Zurückgehen «verschwunden» meldet, ist auf dem iPhone kein Verlass.
            guard oldValue != selectedNote, let oldValue, let editor = openEditor, editor.url == oldValue else { return }
            Task { await editor.flush() }
        }
    }

    /// Nach dem + der Tab-Leiste: Die nächste geöffnete Notiz wird zum neuen Tab.
    private(set) var addingTab = false
    @ObservationIgnored private var selectionBeforeAddingTab: SidebarItem? = .inbox

    /// Die offenen Notizen als Tabs. Im Hauptfenster bleiben sie über einen
    /// Neustart erhalten, abgelöste Fenster merkt sich das System selbst.
    private(set) var tabs = NoteTabs() {
        didSet {
            guard oldValue != tabs, keepsTabs else { return }
            UserDefaults.standard.set(tabs.urls.compactMap(vault.relativePath(of:)), forKey: Self.tabsKey)
            UserDefaults.standard.set(tabs.active.flatMap(vault.relativePath(of:)), forKey: Self.activeTabKey)
        }
    }
    private let keepsTabs: Bool
    private static let tabsKey = "notizTabs"
    private static let sortFieldKey = "notizSortierung"
    private static let sortAscendingKey = "notizSortierungAufsteigend"

    private static func savedNoteSort() -> NoteSort {
        guard let raw = UserDefaults.standard.string(forKey: sortFieldKey),
              let field = NoteSort.Field(rawValue: raw) else { return NoteSort() }
        return NoteSort(field: field, ascending: UserDefaults.standard.bool(forKey: sortAscendingKey))
    }
    private static let activeTabKey = "notizTabAktiv"

    /// Gewähltes Hilfe-Thema (`HelpTopic.id`).
    var helpTopic: String?

    /// Eben angelegte Notiz: Der Editor setzt dann den Fokus auf den Titel.
    var justCreatedNote: URL?
    /// Aus einer Vorlage mit `{{cursor}}` bzw. Beispieltext: Der Editor setzt
    /// den Cursor an diese Stelle (Text ohne Kopf, UTF-16).
    var pendingCursor: (url: URL, offset: Int?)?
    /// Aus einer Vorlage mit `{{? …}}` bzw. `{{cursor}}` im Titel: diese
    /// Stelle im Titelfeld markieren.
    var pendingTitleSelection: (url: URL, range: NSRange)?
    /// Vorlage mit Rückfragen (`{{frage: …}}`, `{{wahl: …}}`), die gerade beantwortet werden.
    var askingTemplate: AskingTemplate?

    struct AskingTemplate: Identifiable {
        let url: URL
        let questions: [TemplateQuestion]
        var id: URL { url }
    }

    var errorMessage: String?

    /// Zählt jedes Neueinlesen hoch. Der Editor prüft dann, ob seine Datei von
    /// aussen geändert wurde.
    private(set) var revision = 0

    private var monitor: VaultMonitor?

    /// Such-Index im Cache-Ordner dieses Geräts. `nil`, falls er sich nicht
    /// öffnen liess. Dann gibt es keine Suche, alles andere funktioniert.
    private var index: SearchIndex?

    /// Der gerade offene Editor. Vor jeder Operation, die seine Datei betrifft
    /// (verschieben, löschen, Ordner umbenennen …), wird zuerst gespeichert.
    /// Sonst würde ein später Speichervorgang die Datei am alten Ort neu anlegen.
    @ObservationIgnored var openEditor: EditorHandle?

    /// Lokale Vorschau der Ordner und Notizlisten (nur Hauptfenster), damit
    /// beim Start sofort etwas da ist, auch wenn iCloud noch lädt.
    private var snapshot: VaultSnapshot?
    private static let snapshotURL = URL.applicationSupportDirectory.appending(path: "hirni-vorschau.json")

    /// - Parameter windowTabs: Eigenes Fenster mit diesen Tabs; sonst Hauptfenster.
    init(vault: Vault, windowTabs: [URL]? = nil) {
        self.vault = vault
        keepsTabs = windowTabs == nil
        if keepsTabs {
            let snapshot = VaultSnapshot.load(from: Self.snapshotURL)
            self.snapshot = snapshot
            folders = snapshot.folderNodes(in: vault)
            notes = noteSort.apply(snapshot.notes(in: vault.inboxURL, vault: vault) ?? [])
        }
        if let windowTabs {
            tabs = NoteTabs(urls: windowTabs, active: windowTabs.first)
        } else {
            let paths = UserDefaults.standard.stringArray(forKey: Self.tabsKey) ?? []
            let active = UserDefaults.standard.string(forKey: Self.activeTabKey)
            tabs = NoteTabs(
                urls: paths.map { vault.root.appending(path: $0) },
                active: active.map { vault.root.appending(path: $0) }
            )
        }
    }

    /// Eigenes Fenster ohne Seitenleiste und Liste.
    var isNoteWindow: Bool { !keepsTabs }

    /// Das + der Tab-Leiste: Die nächste geöffnete Notiz wird zum neuen Tab.
    func beginAddingTab() {
        addingTab = true
        #if os(iOS)
        selectedNote = nil
        // Ohne Auswahl zeigt das iPhone die Seitenleiste.
        selectionBeforeAddingTab = sidebarSelection
        sidebarSelection = nil
        #endif
    }

    /// Zurück zum Tab, von dem aus das + gedrückt wurde.
    func cancelAddingTab() {
        addingTab = false
        #if os(iOS)
        sidebarSelection = selectionBeforeAddingTab
        #endif
        selectedNote = tabs.active
    }

    /// «In neuem Tab öffnen».
    func openInNewTab(_ url: URL) {
        tabs.openNew(url)
        selectedNote = url
    }

    /// Schliesst einen Tab. War es der gezeigte, rückt der Nachbar nach.
    func closeTab(_ url: URL) {
        let neighbour = tabs.close(url)
        if selectedNote == url { selectedNote = neighbour }
    }

    /// Der Such-Index ist eine Datei: Alle Fenster teilen sich denselben Zugang.
    private static var sharedIndex: SearchIndex?
    private static func openIndex() throws -> SearchIndex {
        if let sharedIndex { return sharedIndex }
        let index = try SearchIndex(fileURL: URL.cachesDirectory.appending(path: "hirni-suche.sqlite"))
        sharedIndex = index
        return index
    }

    var currentFolderURL: URL? {
        switch sidebarSelection {
        case .inbox, nil: vault.inboxURL
        case .folder(let url): url
        case .tag, .tasks, .trash, .help: nil
        }
    }

    var currentTitle: String {
        switch sidebarSelection {
        case .inbox, nil: VaultLayout.inboxFolderName
        case .folder(let url): url.lastPathComponent
        case .tag(let tag): "#\(tag)"
        case .tasks: "Pendenzen"
        case .trash: "Zuletzt gelöscht"
        case .help: "Hilfe"
        }
    }

    func start() async {
        guard monitor == nil else { return }
        let monitor = VaultMonitor(
            onChange: { [weak self] in Task { await self?.reload() } },
            onStatus: { [weak self] in self?.iCloudStatus = $0 }
        )
        monitor.start()
        self.monitor = monitor
        do {
            index = try Self.openIndex()
        } catch {
            vaultLog.error("Such-Index nicht verfügbar: \(error.localizedDescription, privacy: .public)")
        }
        await perform { try $0.purgeTrash() }
        // Eine frühere Version schrieb «➕ Datum» in Pendenzen; einmal entfernen.
        if !UserDefaults.standard.bool(forKey: "erfasstDatenEntfernt") {
            await perform { $0.removeCreatedDates() }
            UserDefaults.standard.set(true, forKey: "erfasstDatenEntfernt")
        }
        // Vorlagen mit Platzhaltern im Namen: Kurztitel, Muster in den Kopf.
        await perform { $0.shortenTemplateNames() }
        await importShared()
        await reload()
    }

    /// Holt ab, was Teilen-Erweiterung und Widget nicht direkt in den
    /// Hirni-Ordner schreiben konnten (siehe `SharedInbox`, `WidgetCompletions`).
    func importShared() async {
        guard let group = AppGroup.folder else { return }
        let queue = group.appending(path: SharedInbox.queueFolderName, directoryHint: .isDirectory)
        _ = await perform { SharedInbox.importPending(from: queue, into: $0) }
        _ = await perform { WidgetCompletions.apply(from: group, to: $0) }
    }

    /// Tags aus dem Such-Index übernehmen (ohne Index: alle Notizen lesen).
    func refreshTags() async {
        let vault = vault
        let counts: [TagCount]
        if let index, let fromIndex = try? await index.tags() {
            counts = fromIndex.map { TagCount(name: $0.name, count: $0.count) }
        } else {
            counts = await Task.detached { vault.allTags().map { TagCount(name: $0.name, count: $0.count) } }.value
        }
        if counts != tagCounts { tagCounts = counts }
        let names = counts.map(\.name)
        if names != tags { tags = names }
    }

    /// Volltextsuche. `inCurrentFolder` beschränkt auf den gewählten Ordner
    /// (samt Unterordnern).
    func search(_ text: String, inCurrentFolder: Bool) async -> [SearchHit] {
        guard let index else { return [] }
        let folder = inCurrentFolder ? currentFolderURL.flatMap(vault.relativePath(of:)) : nil
        do {
            return try await index.search(text, in: folder, vault: vault)
        } catch {
            vaultLog.error("Suche: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    func reload() async {
        let started = ContinuousClock.now
        defer { vaultLog.debug("reload: \(ContinuousClock.now - started, privacy: .public)") }
        let vault = vault
        let folderURL = currentFolderURL
        let showsTrash = sidebarSelection == .trash
        let selection = sidebarSelection

        // Zuerst, was man sieht: Ordner und Notizliste. Das liest nur die
        // Anfänge der Notizen und ist schnell da, auch wenn iCloud noch lädt.
        let quick = await Task.detached {
            (
                folders: Result { try vault.folderTree() },
                notes: Result { try folderURL.map { try vault.notes(in: $0) } ?? [] },
                trash: Result { showsTrash ? try vault.trashEntries() : [] }
            )
        }.value
        guard selection == sidebarSelection else { return }
        if case .success(let folders) = quick.folders, folders != self.folders { self.folders = folders }
        if case .success(let trash) = quick.trash { self.trash = trash }
        if selection?.isTag != true, case .success(let notes) = quick.notes {
            let sorted = noteSort.apply(notes)
            if sorted != self.notes { self.notes = sorted }
        }
        rememberSnapshot(folders: quick.folders, notes: quick.notes, in: folderURL)

        // Dann der Rest. Zuerst den Such-Index nachführen: Die Tag-Ansicht braucht ihn.
        if let index {
            do {
                try await index.update(from: vault)
            } catch {
                vaultLog.error("Index: \(String(describing: error), privacy: .public)")
            }
        }
        await refreshTags()

        let result = await Task.detached {
            (
                templates: vault.templates(),
                tasks: vault.allTasks(),
                dueDates: vault.dueDates()
            )
        }.value

        if templates != result.templates { templates = result.templates }
        if tasks != result.tasks { tasks = result.tasks }
        if dueDates != result.dueDates { dueDates = result.dueDates }
        tabs.retain { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        #if os(macOS)
        // Aktiver Tab gelöscht: Der Nachbar rückt nach.
        if selectedNote == nil, tabs.urls.count > 1 { selectedNote = tabs.active }
        #endif
        await scheduleReminders()
        Task { [vault] in await CalendarExporter.shared.sync(vault) }
        switch quick.notes {
        case .success:
            if selection?.isTag == true, selection == sidebarSelection {
                let tagged = noteSort.apply(await taggedNotes())
                if tagged != notes { notes = tagged }
            }
        case .failure:
            // Der gewählte Ordner existiert nicht mehr (z. B. auf dem anderen
            // Gerät gelöscht oder umbenannt): zurück zur Inbox.
            if case .folder = sidebarSelection { sidebarSelection = .inbox }
        }
        revision += 1
    }

    /// Vorschau nachführen und lokal sichern (nur Hauptfenster).
    private func rememberSnapshot(folders: Result<[FolderNode], Error>, notes: Result<[NoteSummary], Error>, in folder: URL?) {
        guard var snapshot else { return }
        let before = snapshot
        if case .success(let folders) = folders { snapshot.record(folders: folders, in: vault) }
        if let folder, case .success(let notes) = notes { snapshot.record(notes: notes, in: folder, vault: vault) }
        guard snapshot != before else { return }
        self.snapshot = snapshot
        let url = Self.snapshotURL
        Task {
            let failure = await Task.detached(priority: .utility) { [snapshot] () -> String? in
                do { try snapshot.save(to: url); return nil } catch { return String(describing: error) }
            }.value
            if let failure { vaultLog.error("Vorschau sichern: \(failure, privacy: .public)") }
        }
    }

    private func taggedNotes() async -> [NoteSummary] {
        guard case .tag(let tag) = sidebarSelection, let index,
              let urls = try? await index.notes(withTag: tag, vault: vault)
        else { return [] }
        let vault = vault
        return await Task.detached { vault.summaries(for: urls) }.value
    }

    // MARK: - Notizen

    /// Läuft gerade eine Texterkennung (siehe `newNote(recognizingTextIn:)`).
    var isRecognizingText = false

    /// Neue Notiz aus dem Text auf Fotos (eine Notiz für alle Bilder, in der
    /// gewählten Reihenfolge). Der Titel ist die erste Zeile.
    func newNote(recognizingTextIn images: [Data]) async {
        guard !images.isEmpty else { return }
        isRecognizingText = true
        defer { isRecognizingText = false }
        let text: String
        do {
            text = try await TextRecognizer.text(in: images)
        } catch {
            errorMessage = "Der Text liess sich nicht erkennen: \(error.localizedDescription)"
            return
        }
        guard !text.isEmpty else {
            errorMessage = images.count == 1 ? "Auf dem Bild wurde kein Text gefunden." : "Auf den Bildern wurde kein Text gefunden."
            return
        }
        if sidebarSelection == .trash || sidebarSelection == .tasks || sidebarSelection == .help { sidebarSelection = .inbox }
        let folder = currentFolderURL ?? vault.inboxURL
        let note = SharedItem.recognizedNote(from: text)
        guard let url = await perform({ try $0.createNote(in: folder, title: note.title, text: note.text) }) else { return }
        await reload()
        selectedNote = url
    }

    /// Im Ordner «Vorlagen» entstehen neue Vorlagen, dort gibt es keine Auswahl.
    var offersTemplates: Bool {
        !templates.isEmpty && currentFolderURL?.standardizedFileURL != vault.templatesURL.standardizedFileURL
    }

    /// Neue Notiz, leer oder aus einer Vorlage. Hat die Vorlage Rückfragen,
    /// erscheint zuerst das Blatt dafür (`askingTemplate`).
    func newNote(template: URL? = nil, answers: [String: String]? = nil) async {
        if let template, answers == nil {
            let vault = vault
            let questions = await Task.detached { vault.templateQuestions(template) }.value
            if !questions.isEmpty {
                askingTemplate = AskingTemplate(url: template, questions: questions)
                return
            }
        }
        if sidebarSelection == .trash || sidebarSelection == .tasks || sidebarSelection == .help { sidebarSelection = .inbox }
        let folder = currentFolderURL ?? vault.inboxURL
        // In der Tag-Ansicht bekommt die neue Notiz (in der Inbox) gleich den Tag.
        let tag = if case .tag(let tag) = sidebarSelection { tag } else { String?.none }
        let url: URL?
        if let template {
            let answers = answers ?? [:]
            let created = await perform { vault in
                let created = try vault.createNote(in: folder, fromTemplate: template, answers: answers)
                if let tag { try vault.writeNote("#\(tag) " + vault.readNote(at: created.url), to: created.url) }
                return (url: created.url, cursor: created.cursor.map { $0 + (tag.map { ("#\($0) " as NSString).length } ?? 0) },
                        titleSelection: created.titleSelection)
            }
            url = created?.url
            if let created {
                pendingCursor = (created.url, created.cursor)
                if let range = created.titleSelection { pendingTitleSelection = (created.url, range) }
            }
        } else {
            url = await perform({ try $0.createNote(in: folder, text: tag.map { "#\($0) " } ?? "") })
        }
        guard let url else { return }
        await reload()
        // Aus einer Vorlage hat die Notiz schon einen Titel.
        if template == nil { justCreatedNote = url }
        selectedNote = url
    }

    func newDatabase() async {
        if sidebarSelection == .trash || sidebarSelection?.isTag == true { sidebarSelection = .inbox }
        let folder = currentFolderURL ?? vault.inboxURL
        guard let url = await perform({ try $0.createDatabase(in: folder) }) else { return }
        await reload()
        selectedNote = url
    }

    /// Neue Datenbank, ohne sie zu öffnen (z. B. zum Einbetten in eine Notiz).
    func createDatabase(in folder: URL, title: String) async -> URL? {
        guard let url = await perform({ try $0.createDatabase(in: folder, title: title) }) else { return nil }
        await reload()
        return url
    }

    func read(_ url: URL) async -> String? {
        await perform { try $0.readNote(at: url) }
    }

    /// Liefert das neue Änderungsdatum der Datei, oder `nil` bei einem Fehler.
    func write(_ text: String, to url: URL) async -> Date? {
        let modified = await perform { try $0.writeNote(text, to: url) }
        if modified != nil {
            mergeTags(from: text)
            await reload() // Vorschau und Reihenfolge in der Liste
        }
        return modified
    }

    /// Neue Tags aus einer eben gespeicherten Notiz sofort bekannt machen,
    /// ohne den ganzen Ordner neu zu lesen.
    private func mergeTags(from text: String) {
        let known = Set(tags.map { $0.lowercased() })
        let new = MarkdownSyntax.tags(in: Frontmatter.split(text).body).filter { !known.contains($0.lowercased()) }
        if !new.isEmpty { tags += new }
    }

    // MARK: - Konflikte

    func hasConflict(_ url: URL) -> Bool {
        iCloudStatus.conflicted.contains(url.canonical)
    }

    func downloadProgress(of url: URL) -> Double? {
        iCloudStatus.downloading[url.canonical]
    }

    func conflictVersions(of url: URL) async -> [ConflictVersion] {
        let vault = vault
        return await Task.detached { vault.conflictVersions(of: url) }.value
    }

    func resolveConflict(at url: URL, choice: ConflictChoice) async {
        await openEditor?.flushIfShowing(url)
        await perform { try $0.resolveConflict(at: url, choice: choice) }
        // Der Editor soll den gewählten Stand sofort zeigen, auch wenn iCloud
        // das Datum nicht verändert hat.
        if let editor = openEditor, editor.url == url { await editor.reloadFromDisk() }
        iCloudStatus.conflicted.remove(url.canonical)
        await reload()
    }

    /// Speichert `text` als eigene Notiz neben `note` (Konflikt: beide behalten).
    func saveConflictCopy(text: String, of note: URL) async -> URL? {
        #if os(iOS)
        let device = UIDevice.current.name
        #else
        let device = Host.current().localizedName
        #endif
        let copy = await perform { try $0.saveConflictCopy(text: text, of: note, deviceName: device) }
        await reload()
        return copy
    }

    /// Lesen für den Editor: Ein Fehler wird nicht als Meldung gezeigt,
    /// sondern im Editor selbst.
    func readForEditor(_ url: URL) async -> Result<String, Error> {
        let vault = vault
        return await Task.detached { Result { try vault.readNote(at: url) } }.value
    }

    // MARK: - Anhänge

    /// Kopiert eine Datei als Anhang zur Notiz. Liefert den Markdown-Text.
    /// `source` darf ausserhalb der App liegen (Dateien-App, Finder): Der
    /// Zugriff wird für die Dauer des Kopierens freigeschaltet.
    func importAttachment(copying source: URL, for note: URL) async -> String? {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        return await perform { try $0.importAttachment(copying: source, for: note) }
    }

    func importAttachment(data: Data, fileExtension: String, baseName: String, for note: URL) async -> String? {
        await perform { try $0.importAttachment(data: data, fileExtension: fileExtension, baseName: baseName, for: note) }
    }

    func modificationDate(of url: URL) async -> Date? {
        let vault = vault
        return await Task.detached { vault.modificationDate(of: url) }.value
    }

    /// Benennt um. Die Auswahl passt der Editor selbst an, weil er die Datei
    /// gerade offen hat.
    func renameNote(_ url: URL, to title: String) async -> URL? {
        guard let newURL = await perform({ try $0.renameNote(at: url, to: title) }) else { return nil }
        tabs.replace(url, with: newURL)
        await reload()
        return newURL
    }

    func deleteNote(_ url: URL) async {
        await closeEditor(ifAffectedBy: url)
        guard await perform({ try $0.moveToTrash(url) }) != nil else { return }
        await reload()
    }

    func duplicateNote(_ url: URL) async {
        await openEditor?.flushIfShowing(url)
        guard let copy = await perform({ try $0.duplicateNote(at: url) }) else { return }
        await reload()
        selectedNote = copy
    }

    // MARK: - Pendenzen

    /// Abhaken bzw. wieder öffnen, direkt in der Notiz.
    func setTask(_ task: TaskItem, done: Bool) async {
        await changeTask(task) { TaskLine.setDone(done, line: $0) }
    }

    func dueDate(of task: TaskItem) -> Date? {
        dueDates.due(for: task.dueKey(in: vault))
    }

    /// Neue Pendenz ohne eigene Notiz: landet in der Notiz «Pendenzen» in der
    /// Inbox (wie bei Kurzbefehl und Menüleiste), auf Wunsch mit Kategorie
    /// und Stichtag.
    func addTask(_ text: String, category: String?, due: Date?) async {
        var line = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        if let category = category?.trimmingCharacters(in: .whitespaces), !category.isEmpty,
           !MarkdownSyntax.tags(in: line).contains(where: { $0.caseInsensitiveCompare(category) == .orderedSame }) {
            line += " #" + category.replacingOccurrences(of: " ", with: "-")
        }
        let toAdd = line
        guard let note = await perform({ try $0.quickTask(toAdd) }) else { return }
        await reload()
        if let due, let task = tasks.last(where: { $0.note == note && !$0.isDone && $0.text == toAdd }) {
            await setDueDate(due, for: task)
        }
    }

    /// Stichtag setzen oder (`nil`) entfernen. Steht nicht in der Notiz.
    func setDueDate(_ date: Date?, for task: TaskItem) async {
        // Gleich beim ersten Stichtag fragen, nicht erst wenn eine Erinnerung ansteht.
        if date != nil { await ReminderScheduler.shared.requestPermission() }
        var dates = dueDates
        dates.set(date, for: task.dueKey(in: vault))
        dueDates = dates
        let toSave = dates
        await perform { try $0.saveDueDates(toSave) }
        await scheduleReminders()
    }

    /// Mitteilungen am Stichtag neu planen und das Widget nachführen (beides
    /// nur, wenn sich etwas geändert hat).
    private func scheduleReminders() async {
        await ReminderScheduler.shared.update(TaskReminders.plan(tasks: tasks, dueDates: dueDates, in: vault))
        WidgetData.publish(WidgetSnapshot.make(tasks: tasks, dueDates: dueDates, in: vault))
    }

    // MARK: - Links auf Notizen

    func linkTargets(excluding note: URL?) async -> [NoteLink.Target] {
        let vault = vault
        return await Task.detached { vault.linkTargets(excluding: note) }.value
    }

    /// Markdown für einen Link; die Zielnotiz bekommt nötigenfalls ihre Kennung.
    func linkMarkdown(to note: URL, label: String?) async -> String? {
        await perform { try $0.linkMarkdown(to: note, label: label) }
    }

    /// Beschriftung und Pfad der Links nachführen (Ziel umbenannt oder verschoben).
    func refreshingLinks(in text: String) async -> String {
        guard text.contains("hirni://notiz?id=") else { return text }
        let vault = vault
        return await Task.detached { vault.refreshingNoteLinks(in: text) }.value
    }

    /// Sprung aus Mitteilung, Widget, Kurzbefehl oder Kalender: eine Notiz
    /// (bzw. Datenbank) in ihrem Ordner öffnen oder die Pendenzen zeigen.
    func open(_ destination: AppDestination) {
        switch destination {
        case .tasks:
            sidebarSelection = .tasks
        case .note(let path):
            open(file: vault.root.appending(path: path))
        case .link(let link):
            let vault = vault
            Task {
                guard let url = await Task.detached(operation: { vault.resolve(link: link) }).value else {
                    errorMessage = "Diese Notiz gibt es nicht mehr. Vielleicht liegt sie in «Zuletzt gelöscht»."
                    return
                }
                show(url)
            }
        }
    }

    /// Öffnet eine Datei, zum Beispiel beim Start eines eigenen Notiz-Fensters.
    func open(file url: URL) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            errorMessage = "Diese Notiz gibt es nicht mehr."
            return
        }
        show(url)
    }

    private func show(_ url: URL) {
        // Den Ordner der Notiz zeigen, damit die Liste daneben passt.
        let folder = url.deletingLastPathComponent()
        sidebarSelection = folder.standardizedFileURL == vault.inboxURL.standardizedFileURL ? .inbox : .folder(folder)
        selectedNote = url
    }

    /// Kategorie = erster Tag der Zeile; `nil` entfernt ihn.
    func setTaskCategory(_ task: TaskItem, _ category: String?) async {
        await changeTask(task) { TaskLine.setCategory(category, line: $0) }
    }

    /// Pendenz aus ihrer Notiz löschen (die ganze Zeile), samt Stichtag.
    func deleteTask(_ task: TaskItem) async {
        await openEditor?.flushIfShowing(task.note)
        await perform { vault in
            let current = vault.allTasks(in: task.note).first { $0.line == task.line && $0.text == task.text }
                ?? vault.allTasks(in: task.note).first { $0.text == task.text }
            guard let current else { throw TaskError.changed }
            try vault.deleteTask(current)
        }
        await reload()
        if let editor = openEditor, editor.url == task.note { await editor.reloadFromDisk() }
    }

    private func changeTask(_ task: TaskItem, _ change: @escaping @Sendable (String) -> String) async {
        // Ist die Notiz offen, zuerst speichern; danach liest der Editor die
        // geänderte Datei wieder ein. Beim Speichern kann sich die Zeile
        // ändern (Erfasst-Datum), darum die Pendenz frisch suchen.
        await openEditor?.flushIfShowing(task.note)
        await perform { vault in
            let current = vault.allTasks(in: task.note).first { $0.line == task.line && $0.text == task.text }
                ?? vault.allTasks(in: task.note).first { $0.text == task.text }
            guard let current else { throw TaskError.changed }
            try vault.updateTask(current, change)
        }
        await reload()
        if let editor = openEditor, editor.url == task.note { await editor.reloadFromDisk() }
    }

    // MARK: - Zeilen-Seiten

    func rowPages(for database: URL) async -> [String: URL] {
        let vault = vault
        return await Task.detached { vault.rowPages(for: database) }.value
    }

    /// Seite der Zeile, wird bei Bedarf angelegt.
    func rowPage(for database: URL, rowID: String, title: String, template: URL?, values: [String: String]) async -> URL? {
        guard let page = await perform({
            try $0.rowPage(for: database, rowID: rowID, title: title, template: template, values: values)
        }) else { return nil }
        await reload()
        return page
    }

    func setPinned(_ pinned: Bool, note url: URL) async {
        await openEditor?.flushIfShowing(url)
        await perform { try $0.setPinned(pinned, note: url) }
        // Das Änderungsdatum bleibt beim Anpinnen gleich. Der Editor bemerkt
        // die Änderung darum nicht von selbst und muss den Kopf neu lesen.
        if let editor = openEditor, editor.url == url { await editor.reloadHeader() }
        await reload()
    }

    /// Verschiebt eine Notiz oder einen Ordner. Wird ein Ordner verschoben, der
    /// gerade in der Seitenleiste gewählt ist, wandert die Auswahl mit.
    func move(_ url: URL, to folder: URL) async {
        guard vault.contains(url), vault.contains(folder) || folder == vault.root else { return }
        guard url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL else { return }
        await closeEditor(ifAffectedBy: url)
        guard let newURL = await perform({ try $0.move(url, to: folder) }) else { return }
        followSelection(from: url, to: newURL)
        await reload()
    }

    // MARK: - Ordner

    /// Die Unterordner des gewählten Ordners (nicht der Inbox).
    var currentSubfolders: [FolderNode] {
        guard case .folder(let url) = sidebarSelection else { return [] }
        func find(_ nodes: [FolderNode]) -> FolderNode? {
            for node in nodes {
                if node.url.standardizedFileURL == url.standardizedFileURL { return node }
                if let found = find(node.children) { return found }
            }
            return nil
        }
        return find(folders)?.children ?? []
    }

    func newFolder(in parent: URL?, name: String) async {
        let parent = parent ?? vault.root
        guard let url = await perform({ try $0.createFolder(in: parent, name: name) }) else { return }
        await reload()
        sidebarSelection = .folder(url)
    }

    func renameFolder(_ url: URL, to name: String) async {
        await closeEditor(ifAffectedBy: url)
        guard let newURL = await perform({ try $0.renameFolder(at: url, to: name) }) else { return }
        followSelection(from: url, to: newURL)
        await reload()
    }

    func deleteFolder(_ url: URL) async {
        await closeEditor(ifAffectedBy: url)
        guard await perform({ try $0.moveToTrash(url) }) != nil else { return }
        if case .folder(let selected) = sidebarSelection, selected.isInside(url) {
            sidebarSelection = .inbox
        }
        await reload()
    }

    // MARK: - Zuletzt gelöscht

    func restore(_ entry: TrashEntry) async {
        await perform { try $0.restore(entry) }
        await reload()
    }

    func emptyTrash() async {
        await perform { try $0.emptyTrash() }
        await reload()
    }

    func deletePermanently(_ entry: TrashEntry) async {
        await perform { try $0.deletePermanently(entry) }
        await reload()
    }

    // MARK: - Hilfen

    /// Speichert und schliesst den Editor, falls seine Datei `url` ist oder in
    /// `url` liegt.
    private func closeEditor(ifAffectedBy url: URL) async {
        if let editor = openEditor, editor.url.isInside(url) {
            await editor.flush()
            openEditor = nil
        }
        if let selectedNote, selectedNote.isInside(url) {
            self.selectedNote = nil
        }
    }

    /// Wurde der gewählte Ordner (oder einer seiner Elternordner) verschoben
    /// oder umbenannt, zeigt die Seitenleiste danach auf den neuen Ort.
    private func followSelection(from oldURL: URL, to newURL: URL) {
        guard case .folder(let selected) = sidebarSelection, selected.isInside(oldURL) else { return }
        let suffix = selected.standardizedFileURL.pathComponents
            .dropFirst(oldURL.standardizedFileURL.pathComponents.count)
        sidebarSelection = .folder(suffix.reduce(newURL) { $0.appending(path: $1, directoryHint: .isDirectory) })
    }

    /// Führt eine Dateioperation im Hintergrund aus. Fehler erscheinen als Hinweis.
    @discardableResult
    private func perform<T: Sendable>(_ work: @escaping @Sendable (Vault) throws -> T) async -> T? {
        let vault = vault
        let started = ContinuousClock.now
        defer { vaultLog.debug("perform: \(ContinuousClock.now - started, privacy: .public)") }
        do {
            return try await Task.detached { try work(vault) }.value
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

/// Verbindung zum offenen Editor, damit der Store ihn vor Dateioperationen
/// speichern lassen kann.
struct EditorHandle {
    let url: URL
    let flush: () async -> Void
    let reloadHeader: () async -> Void
    let reloadFromDisk: () async -> Void

    func flushIfShowing(_ noteURL: URL) async {
        if url == noteURL { await flush() }
    }
}

extension SidebarItem {
    var isTag: Bool {
        if case .tag = self { true } else { false }
    }
}
