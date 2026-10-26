import HirniKit
import Observation
import SwiftUI

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

    init(index: Int, owner: NoteTables) {
        self.index = index
        self.owner = owner
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
    }

    private func rowView(_ row: Int, table: MarkdownTable) -> some View {
        HStack(spacing: 0) {
            Group {
                if row > 0 { rowMenu(row, count: table.rows.count) } else { Color.clear }
            }
            .frame(width: Self.gutterWidth, height: Self.rowHeight)
            ForEach(0..<table.columnCount, id: \.self) { column in
                TextField(row == 0 ? "Titel" : "", text: cell(row, column))
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

    private func cell(_ row: Int, _ column: Int) -> Binding<String> {
        Binding(
            get: {
                let rows = model.table.rows
                return rows.indices.contains(row) && rows[row].indices.contains(column) ? rows[row][column] : ""
            },
            set: { value in
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
