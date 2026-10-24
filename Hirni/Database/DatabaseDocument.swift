import Foundation
import HirniKit
import Observation
import SwiftUI // für Array.move(fromOffsets:toOffset:)

/// Eine geöffnete Datenbank: Laden, Ändern, automatisch Speichern.
///
/// Wie beim Notiz-Editor wird vor jedem Speichern geprüft, ob die Datei
/// inzwischen anderswo geändert wurde. Dann wird Zelle für Zelle
/// zusammengeführt (`DatabaseMerge`), statt zu überschreiben.
@Observable
final class DatabaseDocument {
    let store: VaultStore
    private(set) var url: URL

    private(set) var database = Database(fields: [])
    private(set) var isLoaded = false
    private(set) var loadError: String?
    /// Hinweis nach einem Zusammenführen mit Konflikten.
    var mergeNotice: String?

    @ObservationIgnored private var saved: Database?
    @ObservationIgnored private var savedModified: Date = .distantPast
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(store: VaultStore, url: URL) {
        self.store = store
        self.url = url
    }

    var title: String { Vault.title(of: url) }
    private var hasUnsavedChanges: Bool { saved != database }

    // MARK: - Laden

    func load() async {
        switch await store.readForEditor(url) {
        case .success(let text):
            do {
                database = try DatabaseFile.parse(text)
                saved = database
                savedModified = await store.modificationDate(of: url) ?? .now
                loadError = nil
                isLoaded = true
            } catch {
                loadError = error.localizedDescription
            }
        case .failure:
            loadError = "Die Datei ist keine lesbare Textdatei (UTF-8). hirni verändert sie nicht."
        }
        register()
    }

    /// Wurde die Datei anderswo geändert und gibt es hier nichts Ungespeichertes,
    /// wird neu geladen. Sonst führt `save()` zusammen.
    func reloadIfChangedElsewhere() async {
        guard isLoaded, let modified = await store.modificationDate(of: url),
              modified.timeIntervalSince(savedModified) > 0.5
        else { return }
        if hasUnsavedChanges {
            await save()
        } else {
            await load()
        }
    }

    // MARK: - Ändern

    func value(row id: String, field: String) -> String {
        database.rows.first { $0.id == id }?[field] ?? ""
    }

    func setValue(_ raw: String, row id: String, field: String) {
        guard let index = database.rows.firstIndex(where: { $0.id == id }), database.rows[index][field] != raw else { return }
        database.rows[index][field] = raw
        scheduleSave()
    }

    @discardableResult
    func addRow() -> String {
        let row = Row()
        database.rows.append(row)
        scheduleSave()
        return row.id
    }

    func deleteRows(_ ids: Set<String>) {
        database.rows.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    func moveRows(from source: IndexSet, to destination: Int) {
        database.rows.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    /// Wie viele Werte bei diesen Feldänderungen verloren gingen (für die Warnung).
    func lostValues(applying edits: [FieldEdit]) -> Int {
        apply(edits, to: database).lost
    }

    func updateFields(_ edits: [FieldEdit]) {
        database = apply(edits, to: database).database
        scheduleSave()
    }

    /// Felder umbenennen, Typ ändern, löschen, neu anlegen. Werte, die nach
    /// einer Typ- oder Optionsänderung nicht mehr passen, werden geleert.
    private func apply(_ edits: [FieldEdit], to database: Database) -> (database: Database, lost: Int) {
        var result = database
        var lost = 0
        let keptOriginals = Set(edits.compactMap(\.originalName))

        for name in database.fields.map(\.name) where !keptOriginals.contains(name) {
            for index in result.rows.indices where !result.rows[index][name].isEmpty {
                result.rows[index][name] = ""
                lost += 1
            }
        }
        for edit in edits {
            guard let original = edit.originalName, let old = database.field(named: original) else { continue }
            for index in result.rows.indices {
                var value = result.rows[index][original]
                if original != edit.field.name {
                    result.rows[index][original] = ""
                }
                if (old.type != edit.field.type || old.options != edit.field.options), !CellValue.fits(value, edit.field) {
                    value = ""
                    lost += 1
                }
                result.rows[index][edit.field.name] = value
            }
        }
        result.fields = edits.map(\.field)
        return (result, lost)
    }

    // MARK: - Speichern

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    func save() async {
        guard isLoaded, hasUnsavedChanges, let base = saved else { return }
        var toWrite = database

        if let diskModified = await store.modificationDate(of: url),
           diskModified.timeIntervalSince(savedModified) > 0.5,
           case .success(let text) = await store.readForEditor(url),
           let theirs = try? DatabaseFile.parse(text), theirs != base {
            let merged = DatabaseMerge.merge(base: base, mine: database, theirs: theirs)
            toWrite = merged.database
            database = merged.database
            if merged.conflicts > 0 {
                mergeNotice = merged.conflicts == 1
                    ? "Ein Wert wurde gleichzeitig anderswo geändert. Deine Eingabe wurde behalten."
                    : "\(merged.conflicts) Werte wurden gleichzeitig anderswo geändert. Deine Eingaben wurden behalten."
            }
        }

        if let modified = await store.write(DatabaseFile.serialize(toWrite), to: url) {
            saved = toWrite
            savedModified = modified
        }
    }

    // MARK: - Titel

    func rename(to newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != title else { return }
        await save()
        guard let newURL = await store.renameNote(url, to: trimmed) else { return }
        url = newURL
        savedModified = await store.modificationDate(of: newURL) ?? savedModified
        register()
        store.selectedNote = newURL
    }

    /// Beim Store anmelden: Vor Verschieben/Löschen wird zuerst gespeichert.
    private func register() {
        store.openEditor = EditorHandle(
            url: url,
            flush: { [weak self] in await self?.save() },
            reloadHeader: {},
            reloadFromDisk: { [weak self] in await self?.load() }
        )
    }

    func close() async {
        saveTask?.cancel()
        await save()
        if store.openEditor?.url == url { store.openEditor = nil }
    }
}

/// Ein Feld im Felder-Editor. `originalName` ist `nil` für neue Felder.
struct FieldEdit: Identifiable, Equatable {
    let id = UUID()
    let originalName: String?
    var field: Field
}
