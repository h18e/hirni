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
    /// Zeilen mit eigener Seite: `id` → Notiz.
    private(set) var rowPages: [String: URL] = [:]

    /// Gewählte Ansicht (nur auf diesem Gerät, wird nicht gespeichert).
    private(set) var selectedViewName: String?
    /// Eben angelegte Zeilen bleiben sichtbar, auch wenn sie den Filter nicht erfüllen.
    private(set) var recentlyAdded: Set<String> = []

    @ObservationIgnored private var saved: Database?
    @ObservationIgnored private var savedModified: Date = .distantPast
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// In eine Notiz eingebettet: Dann ist die Notiz beim Store angemeldet,
    /// nicht die Datenbank.
    let isEmbedded: Bool

    init(store: VaultStore, url: URL, isEmbedded: Bool = false) {
        self.store = store
        self.url = url
        self.isEmbedded = isEmbedded
    }

    var title: String { Vault.title(of: url) }

    // MARK: - Ansichten

    /// Die gewählte Ansicht. Gibt es noch keine, eine ungespeicherte «Alle».
    var currentView: SavedView {
        database.views.first { $0.name == selectedViewName } ?? database.views.first ?? SavedView(name: "Alle")
    }

    var result: QueryResult {
        DatabaseQuery.run(currentView, on: database, alwaysShowing: recentlyAdded)
    }

    var visibleFields: [Field] {
        let hidden = Set(currentView.hiddenFields ?? [])
        let fields = database.fields.filter { !hidden.contains($0.name) }
        return fields.isEmpty ? Array(database.fields.prefix(1)) : fields
    }

    func selectView(_ name: String) {
        selectedViewName = name
        recentlyAdded = []
    }

    /// Ändert die gewählte Ansicht. Die ungespeicherte «Alle» wird dabei gespeichert.
    func updateView(_ change: (inout SavedView) -> Void) {
        var view = currentView
        change(&view)
        if let index = database.views.firstIndex(where: { $0.name == currentView.name }) {
            database.views[index] = view
        } else {
            database.views.append(view)
        }
        selectedViewName = view.name
        scheduleSave()
    }

    /// Datumsfeld für den Apple Kalender «Hirni», `nil` = nicht im Kalender.
    func setCalendarField(_ name: String?) {
        guard database.calendarField != name else { return }
        database.calendarField = name
        scheduleSave()
    }

    func addView(kind: ViewKind = .table) {
        if database.views.isEmpty { database.views.append(currentView) } // «Alle» behalten
        var view = SavedView(name: uniqueViewName(kind == .table ? "Ansicht" : kind.label), kind: kind)
        if kind == .calendar {
            view.dateField = database.fields.first { $0.type == .date }?.name
            view.colorField = database.fields.first { $0.type == .select }?.name
        }
        if kind == .chart {
            view.chart = ChartModel.defaultSettings(for: database)
        }
        database.views.append(view)
        selectView(view.name)
        scheduleSave()
    }

    func duplicateView(_ name: String) {
        guard var view = database.views.first(where: { $0.name == name }) ?? (name == currentView.name ? currentView : nil) else { return }
        if database.views.isEmpty { database.views.append(view) }
        view.name = uniqueViewName(name + " Kopie")
        database.views.append(view)
        selectView(view.name)
        scheduleSave()
    }

    func renameView(_ name: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != name, !database.views.contains(where: { $0.name == trimmed }) else { return }
        if database.views.isEmpty { database.views.append(currentView) }
        guard let index = database.views.firstIndex(where: { $0.name == name }) else { return }
        database.views[index].name = trimmed
        if selectedViewName == name || selectedViewName == nil { selectedViewName = trimmed }
        scheduleSave()
    }

    func deleteView(_ name: String) {
        database.views.removeAll { $0.name == name }
        if selectedViewName == name { selectedViewName = database.views.first?.name }
        scheduleSave()
    }

    private func uniqueViewName(_ base: String) -> String {
        var number = 1
        func name() -> String { number == 1 ? base : "\(base) \(number)" }
        while database.views.contains(where: { $0.name == name() }) || name() == currentView.name { number += 1 }
        return name()
    }
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
            loadError = "Die Datei ist keine lesbare Textdatei (UTF-8). Hirni verändert sie nicht."
        }
        register()
        await refreshRowPages()
    }

    // MARK: - Zeilen-Seiten

    /// Seiten können auch anderswo entstehen (Claude, anderes Gerät), darum
    /// bei jeder Änderung im hirni-Ordner neu nachsehen.
    func refreshRowPages() async {
        let pages = await store.rowPages(for: url)
        if pages != rowPages { rowPages = pages }
    }

    /// Öffnet die Seite der Zeile, legt sie bei Bedarf an (Titel = erstes
    /// Feld), auf Wunsch aus einer Vorlage mit den Werten des Eintrags.
    func page(for rowID: String, template: URL? = nil) async -> URL? {
        if let page = rowPages[rowID] { return page }
        let title = database.fields.first.map { CellValue.display(value(row: rowID, field: $0.name), for: $0) } ?? ""
        var values: [String: String] = [:]
        for field in database.fields { values[field.name] = CellValue.display(value(row: rowID, field: field.name), for: field) }
        let page = await store.rowPage(for: url, rowID: rowID, title: title, template: template, values: values)
        await refreshRowPages()
        return page
    }

    /// Wurde die Datei anderswo geändert und gibt es hier nichts Ungespeichertes,
    /// wird neu geladen. Sonst führt `save()` zusammen.
    func reloadIfChangedElsewhere() async {
        await refreshRowPages()
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
        guard let row = database.rows.first(where: { $0.id == id }) else { return "" }
        // Formeln stehen nicht in der Datei: hier ausrechnen.
        if let definition = database.field(named: field), definition.type == .formula {
            return Formula.rawValue(of: definition, row: row, in: database)
        }
        return row[field]
    }

    func setValue(_ raw: String, row id: String, field: String) {
        guard database.field(named: field)?.type != .formula,
              let index = database.rows.firstIndex(where: { $0.id == id }), database.rows[index][field] != raw else { return }
        database.rows[index][field] = raw
        scheduleSave()
    }

    /// Neuer Eintrag. Werte aus einfachen Filtern der Ansicht werden
    /// übernommen (z. B. Filter «Kategorie ist Essen» → Kategorie = Essen).
    /// `values`: Vorgaben, z. B. das Datum des angetippten Kalendertags.
    @discardableResult
    func addRow(values: [String: String] = [:]) -> String {
        var row = Row(values: values)
        for rule in currentView.filters ?? [] {
            guard let field = database.field(named: rule.field), let value = rule.value, !value.isEmpty else {
                if rule.condition == .checked { row[rule.field] = CellValue.raw(bool: true) }
                continue
            }
            switch (field.type, rule.condition) {
            case (.select, .equals), (.text, .equals), (.number, .equals), (.date, .equals), (.url, .equals):
                row[field.name] = value
            case (.multiSelect, .contains):
                row[field.name] = CellValue.raw(list: CellValue.list(row[field.name]) + [value])
            default:
                break
            }
        }
        database.rows.append(row)
        recentlyAdded.insert(row.id)
        scheduleSave()
        return row.id
    }

    func deleteRows(_ ids: Set<String>) {
        database.rows.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    /// Spalte verschieben (Mac: Überschrift ziehen), vor `target` oder ans Ende.
    func moveField(_ name: String, before target: String?) {
        let before = database.fields
        database.moveField(name, before: target)
        if database.fields != before { scheduleSave() }
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
            let renames = edit.optionRenames
            for index in result.rows.indices {
                var value = CellValue.renamingOptions(result.rows[index][original], renames, type: old.type)
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
        // Kalender: Feld umbenannt → mitnehmen, gelöscht oder kein Datum mehr → aus.
        if let name = result.calendarField {
            let edit = edits.first { $0.originalName == name }
            result.calendarField = edit?.field.type == .date ? edit?.field.name : nil
        }
        // Formeln nachführen: [Alt] → [Neu].
        for (old, new) in edits.compactMap({ edit in edit.originalName.map { ($0, edit.field.name) } }) where old != new {
            for index in result.fields.indices {
                if let formula = result.fields[index].formula {
                    result.fields[index].formula = Formula.renamingField(old, to: new, in: formula)
                }
            }
        }
        // Ansichten nachführen: umbenannte Felder in Regeln anpassen, gelöschte entfernen.
        let renames = edits.compactMap { edit in edit.originalName.map { ($0, edit.field.name) } }
        for index in result.views.indices {
            for edit in edits { if let original = edit.originalName { result.views[index].renameOptions(of: original, edit.optionRenames) } }
            for (old, new) in renames where old != new { result.views[index].renameField(old, to: new) }
            for name in database.fields.map(\.name) where !keptOriginals.contains(name) {
                result.views[index].renameField(name, to: nil)
            }
        }
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
        await refreshRowPages()
    }

    /// Beim Store anmelden: Vor Verschieben/Löschen wird zuerst gespeichert.
    /// Auch nach dem Schliessen einer Zeilen-Seite, die sich angemeldet hatte.
    func register() {
        guard !isEmbedded else { return }
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
    /// Ursprünglicher Name jeder Option (`nil` für neue), in derselben
    /// Reihenfolge wie `field.options`. So werden Umbenennungen erkannt.
    var optionOrigins: [String?]

    init(originalName: String?, field: Field) {
        self.originalName = originalName
        self.field = field
        optionOrigins = originalName == nil ? (field.options ?? []).map { _ in nil } : (field.options ?? []).map(Optional.some)
    }

    /// Umbenannte Optionen: alt → neu.
    var optionRenames: [String: String] {
        var renames: [String: String] = [:]
        for (origin, name) in zip(optionOrigins, field.options ?? []) {
            if let origin, origin != name { renames[origin] = name }
        }
        return renames
    }
}
