import HirniKit
import Observation
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Die gewöhnlichen Markdown-Tabellen einer Notiz, als bearbeitbare Raster.
///
/// Jede Tabelle hat ein Modell, das über ihre Position (1., 2. … Tabelle)
/// gefunden wird. So bleibt das Raster bestehen, während man tippt und der
/// Text sich bei jeder Eingabe ändert.
@MainActor
final class NoteTables {
    /// Die Tabelle an Position `index` wurde im Raster geändert.
    var onChange: (_ index: Int, _ table: MarkdownTable) -> Void = { _, _ in }
    /// Die Höhe hat sich geändert (Zeile dazu oder weg).
    var onLayoutChange: () -> Void = {}
    /// Ein Griff wird gezogen: Solange darf die Notiz nicht scrollen, sonst
    /// übernimmt sie die Bewegung.
    var onDragging: (Bool) -> Void = { _ in }

    /// In Vorlagen sind Beispieltexte gewöhnlicher Text, mit Klammern.
    var hintsAsText = false
    /// Tab in der letzten Zelle der Tabelle an Position `index`.
    var onTabOut: (_ index: Int) -> Void = { _ in }
    /// Die Zelle mit dem Fokus. Tab behandelt Hirni selbst: Das System würde
    /// aus der letzten Zelle zum nächsten Eingabefeld springen, also in die
    /// nächste Tabelle, und Beispieltexte im Text dazwischen auslassen.
    var focused: (model: TableModel, cell: TableCell)?

    #if os(macOS)
    /// Am Mac verarbeitet das Textfeld Tab selbst, bevor SwiftUI es sieht.
    nonisolated(unsafe) private var tabMonitor: Any?

    init() {
        tabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isTab = event.keyCode == 48 && !event.modifierFlags.contains(.shift)
            guard isTab else { return event }
            let handled = MainActor.assumeIsolated {
                guard let self, let focused = self.focused else { return false }
                focused.model.tab(from: focused.cell)
                return true
            }
            return handled ? nil : event
        }
    }

    deinit {
        if let tabMonitor { NSEvent.removeMonitor(tabMonitor) }
    }
    #endif

    private var models: [TableModel] = []

    func model(at index: Int) -> TableModel {
        while models.count <= index { models.append(TableModel(index: models.count, owner: self)) }
        return models[index]
    }

    /// Stand aus dem Text übernehmen. Weicht er nur in Leerzeichen am Rand
    /// ab (das Raster hat gerade «Hallo » getippt), bleibt der Stand im Raster.
    func update(from tables: [MarkdownTable]) {
        for (index, table) in tables.enumerated() {
            let model = model(at: index)
            if Self.normalized(model.table.rows) != Self.normalized(table.rows) { model.table = table }
        }
    }

    func height(of table: MarkdownTable) -> CGFloat {
        TableGrid.height(rows: table.rows.count)
    }

    fileprivate func tabOut(of model: TableModel) {
        onTabOut(model.index)
    }

    fileprivate func changed(_ model: TableModel, rowCountChanged: Bool) {
        onChange(model.index, model.table)
        if rowCountChanged { onLayoutChange() }
    }

    private static func normalized(_ rows: [[String]]) -> [[String]] {
        rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }
}

@Observable
@MainActor
final class TableModel {
    let index: Int
    @ObservationIgnored private weak var owner: NoteTables?
    var table = MarkdownTable.empty()
    /// Diese Zelle bekommt den Fokus (Tab, Cursor aus einer Vorlage).
    var focusRequest: TableCell?

    var hintsAsText: Bool { owner?.hintsAsText ?? false }

    init(index: Int, owner: NoteTables) {
        self.index = index
        self.owner = owner
    }

    /// Tab: zur nächsten Zelle, aus der letzten weiter im Text.
    func tab(from cell: TableCell) {
        if let next = table.nextCell(afterRow: cell.row, column: cell.column) {
            focusRequest = TableCell(row: next.row, column: next.column)
        } else {
            owner?.tabOut(of: self)
        }
    }

    /// Meldet die Zelle mit dem Fokus (`nil` = keine mehr in dieser Tabelle).
    func setFocused(_ cell: TableCell?) {
        guard let owner else { return }
        if let cell {
            owner.focused = (self, cell)
        } else if owner.focused?.model === self {
            owner.focused = nil
        }
    }

    func setDragging(_ dragging: Bool) {
        owner?.onDragging(dragging)
    }

    func edit(_ change: (inout MarkdownTable) -> Void) {
        let rows = table.rows.count
        var changed = table
        change(&changed)
        guard changed.rows != table.rows else { return }
        table = changed
        owner?.changed(self, rowCountChanged: rows != table.rows.count)
    }
}

struct TableCell: Hashable {
    let row: Int
    let column: Int
}

/// Eine Tabelle zum direkten Bearbeiten. Über jeder Spalte und vor jeder
/// Zeile ein kleines Menü (einfügen, verschieben, löschen). Am rechten und
/// unteren Rand ein Griff: ziehen fügt Spalten bzw. Zeilen an (zurückziehen
/// entfernt leere wieder), antippen fügt eine an.
struct TableGrid: View {
    let model: TableModel

    #if os(iOS)
    static let columnWidth: CGFloat = 130
    static let rowHeight: CGFloat = 40
    #else
    static let columnWidth: CGFloat = 150
    static let rowHeight: CGFloat = 30
    #endif
    /// Wie weit man für eine Spalte mehr ziehen muss. Auf dem iPhone kürzer:
    /// Der Griff steht dort meist am Bildschirmrand.
    #if os(iOS)
    static let columnDragStep: CGFloat = 40
    #else
    static let columnDragStep: CGFloat = columnWidth
    #endif
    static let stripHeight: CGFloat = 20
    static let gutterWidth: CGFloat = 24
    static let handleSize: CGFloat = 24

    static func height(rows: Int) -> CGFloat {
        stripHeight + CGFloat(rows) * rowHeight + handleSize + 4
    }

    @State private var dragStart: Int?
    @FocusState private var focusedCell: TableCell?
    #if os(iOS)
    /// Auswahl im Feld mit dem Fokus.
    @State private var selection: TextSelection?
    #endif

    var body: some View {
        let table = model.table
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: Self.gutterWidth, height: Self.stripHeight)
                    ForEach(0..<table.columnCount, id: \.self) { column in
                        columnMenu(column, count: table.columnCount)
                            .frame(width: Self.columnWidth, height: Self.stripHeight)
                    }
                }
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(table.rows.indices, id: \.self) { row in
                            rowView(row, table: table)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.35)).padding(.leading, Self.gutterWidth))
                    columnHandle(columns: table.columnCount)
                }
                rowHandle(bodyRows: table.rows.count - 1, columns: table.columnCount)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(dragStart != nil)
        .defaultScrollAnchor(.topLeading, for: .alignment)
        .onChange(of: model.focusRequest, initial: true) { _, request in
            guard let request else { return }
            focusedCell = request
            model.focusRequest = nil
        }
        .onChange(of: focusedCell) { _, cell in
            model.setFocused(cell)
            if let cell { selectHint(in: cell) }
        }
        .onDisappear { model.setFocused(nil) }
    }

    private func rowView(_ row: Int, table: MarkdownTable) -> some View {
        HStack(spacing: 0) {
            Group {
                if row > 0 { rowMenu(row, count: table.rows.count) } else { Color.clear }
            }
            .frame(width: Self.gutterWidth, height: Self.rowHeight)
            ForEach(0..<table.columnCount, id: \.self) { column in
                field(row, column)
                    .focused($focusedCell, equals: TableCell(row: row, column: column))
                    #if os(iOS)
                    .onKeyPress(.tab) {
                        model.tab(from: TableCell(row: row, column: column))
                        return .handled
                    }
                    #endif
                    .textFieldStyle(.plain)
                    .font(row == 0 ? .body.bold() : .body)
                    .padding(.horizontal, 8)
                    .frame(width: Self.columnWidth, height: Self.rowHeight, alignment: .leading)
                    .background(row == 0 ? Color.primary.opacity(0.06) : .clear)
                    .overlay(alignment: .trailing) {
                        if column < table.columnCount - 1 { Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1) }
                    }
                    .overlay(alignment: .bottom) {
                        if row < table.rows.count - 1 { Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1) }
                    }
            }
        }
    }

    @ViewBuilder
    private func field(_ row: Int, _ column: Int) -> some View {
        #if os(iOS)
        TextField(row == 0 ? "Titel" : "", text: cell(row, column), selection: Binding(
            get: { focusedCell == TableCell(row: row, column: column) ? selection : nil },
            set: { if focusedCell == TableCell(row: row, column: column) { selection = $0 } }
        ), prompt: prompt(row, column))
        #else
        TextField(row == 0 ? "Titel" : "", text: cell(row, column), prompt: prompt(row, column))
        #endif
    }

    /// Steht neben dem Beispieltext fester Text in der Zelle, wird beim
    /// Betreten nur der Beispieltext markiert: Tippen ersetzt nur ihn.
    private func selectHint(in cell: TableCell) {
        let raw = rawCell(cell.row, cell.column)
        guard !model.hintsAsText, TemplateFiller.hintText(ofCell: raw) == nil,
              let range = TemplateFiller.hintRangeInDisplay(ofCell: raw) else { return }
        // Das System markiert beim Betreten selbst; danach korrigieren.
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard focusedCell == cell else { return }
            #if os(iOS)
            let display = TemplateFiller.displayCell(raw)
            if let found = Range(range, in: display) { selection = TextSelection(range: found) }
            #else
            (NSApp.keyWindow?.firstResponder as? NSTextView)?.setSelectedRange(range)
            #endif
        }
    }

    private func rawCell(_ row: Int, _ column: Int) -> String {
        let rows = model.table.rows
        return rows.indices.contains(row) && rows[row].indices.contains(column) ? rows[row][column] : ""
    }

    /// Besteht die Zelle nur aus einem Beispieltext, erscheint er grau als
    /// Platzhalter des Felds: Tippen ersetzt ihn.
    private func prompt(_ row: Int, _ column: Int) -> Text? {
        guard !model.hintsAsText, let hint = TemplateFiller.hintText(ofCell: rawCell(row, column)) else {
            return row == 0 ? Text("Titel") : nil
        }
        return Text(hint)
    }

    private func cell(_ row: Int, _ column: Int) -> Binding<String> {
        Binding(
            get: {
                let raw = rawCell(row, column)
                if model.hintsAsText { return raw }
                return TemplateFiller.hintText(ofCell: raw) != nil ? "" : TemplateFiller.displayCell(raw)
            },
            set: { value in
                let raw = rawCell(row, column)
                // Ohne Eingabe bleibt der Beispieltext in der Datei.
                if !model.hintsAsText {
                    if TemplateFiller.hintText(ofCell: raw) != nil, value.isEmpty { return }
                    if value == TemplateFiller.displayCell(raw) { return }
                }
                model.edit { table in
                    guard table.rows.indices.contains(row), table.rows[row].indices.contains(column) else { return }
                    table.rows[row][column] = value
                }
            }
        )
    }

    // MARK: - Menüs

    private func columnMenu(_ column: Int, count: Int) -> some View {
        Menu {
            Button("Spalte links einfügen", systemImage: "arrow.left.to.line") { model.edit { $0.insertColumn(at: column) } }
            Button("Spalte rechts einfügen", systemImage: "arrow.right.to.line") { model.edit { $0.insertColumn(at: column + 1) } }
            Divider()
            if column > 0 {
                Button("Nach links", systemImage: "arrow.left") { model.edit { $0.moveColumn(from: column, to: column - 1) } }
            }
            if column < count - 1 {
                Button("Nach rechts", systemImage: "arrow.right") { model.edit { $0.moveColumn(from: column, to: column + 1) } }
            }
            if count > 1 {
                Divider()
                Button("Spalte löschen", systemImage: "trash", role: .destructive) { model.edit { $0.removeColumn(at: column) } }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        #if os(macOS)
        .menuIndicator(.hidden)
        #endif
        .accessibilityLabel("Spalte \(column + 1)")
    }

    private func rowMenu(_ row: Int, count: Int) -> some View {
        Menu {
            Button("Zeile darüber einfügen", systemImage: "arrow.up.to.line") { model.edit { $0.insertRow(at: row) } }
            Button("Zeile darunter einfügen", systemImage: "arrow.down.to.line") { model.edit { $0.insertRow(at: row + 1) } }
            Divider()
            if row > 1 {
                Button("Nach oben", systemImage: "arrow.up") { model.edit { $0.moveRow(from: row, to: row - 1) } }
            }
            if row < count - 1 {
                Button("Nach unten", systemImage: "arrow.down") { model.edit { $0.moveRow(from: row, to: row + 1) } }
            }
            if count > 2 {
                Divider()
                Button("Zeile löschen", systemImage: "trash", role: .destructive) { model.edit { $0.removeRow(at: row) } }
            }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        #if os(macOS)
        .menuIndicator(.hidden)
        #endif
        .accessibilityLabel("Zeile \(row)")
    }

    // MARK: - Griffe zum Ziehen

    /// Rechts: waagrecht ziehen ändert die Anzahl Spalten.
    private func columnHandle(columns: Int) -> some View {
        handle(systemImage: "plus", label: "Spalte hinzufügen")
            .frame(width: Self.handleSize, height: CGFloat(model.table.rows.count) * Self.rowHeight)
            .padding(.leading, 4)
            .onTapGesture { model.edit { $0.insertColumn(at: $0.columnCount) } }
            .highPriorityGesture(
                // Im Fenster gemessen: Der Griff wandert mit jeder neuen Zeile/Spalte mit.
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStart == nil { model.setDragging(true) }
                        let start = dragStart ?? columns
                        dragStart = start
                        let target = max(1, start + Int((value.translation.width / Self.columnDragStep).rounded()))
                        model.edit { $0.resize(columns: target) }
                    }
                    .onEnded { _ in
                        dragStart = nil
                        model.setDragging(false)
                    }
            )
            #if os(macOS)
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            #endif
    }

    /// Unten: senkrecht ziehen ändert die Anzahl Zeilen.
    private func rowHandle(bodyRows: Int, columns: Int) -> some View {
        handle(systemImage: "plus", label: "Zeile hinzufügen")
            .frame(width: CGFloat(columns) * Self.columnWidth, height: Self.handleSize)
            .padding(.leading, Self.gutterWidth)
            .padding(.top, 4)
            .onTapGesture { model.edit { $0.insertRow(at: $0.rows.count) } }
            .highPriorityGesture(
                // Im Fenster gemessen: Der Griff wandert mit jeder neuen Zeile/Spalte mit.
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStart == nil { model.setDragging(true) }
                        let start = dragStart ?? bodyRows
                        dragStart = start
                        let target = max(1, start + Int((value.translation.height / Self.rowHeight).rounded()))
                        model.edit { $0.resize(bodyRows: target) }
                    }
                    .onEnded { _ in
                        dragStart = nil
                        model.setDragging(false)
                    }
            )
            #if os(macOS)
            .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            #endif
    }

    private func handle(systemImage: String, label: String) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.12))
            .overlay(Image(systemName: systemImage).font(.caption.bold()).foregroundStyle(.secondary))
            .contentShape(Rectangle())
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }
}
