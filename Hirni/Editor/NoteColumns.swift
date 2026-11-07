import HirniKit
import Observation
import SwiftUI

/// Die Spalten-Bereiche einer Notiz (siehe `ColumnBlock`).
///
/// Jede Spalte hat einen eigenen Editor, damit darin alles geht wie sonst auch:
/// Listen, Checkboxen, Tabellen, Bilder, Formatierung. Der Text des Bereichs
/// bleibt in der Notiz, ist dort aber unsichtbar, wie bei Tabellen. Die Modelle
/// werden über die Position (1., 2. … Bereich) gefunden.
@MainActor
final class NoteColumns {
    /// Der Bereich an Position `index` wurde geändert.
    var onChange: (_ index: Int, _ block: ColumnBlock) -> Void = { _, _ in }
    /// Der Bereich an Position `index` soll zu gewöhnlichem Text werden.
    var onDissolve: (_ index: Int) -> Void = { _ in }
    /// Die Höhe eines Bereichs hat sich geändert.
    var onLayoutChange: () -> Void = {}
    /// Die Notiz, zu der die Spalten gehören.
    weak var owner: EditorController?

    private var models: [ColumnBlockModel] = []

    func model(at index: Int) -> ColumnBlockModel {
        while models.count <= index { models.append(ColumnBlockModel(index: models.count, owner: self)) }
        return models[index]
    }

    func update(from blocks: [ColumnBlock]) {
        for (index, block) in blocks.enumerated() {
            model(at: index).update(block.columns)
        }
    }

    /// Platz in der Notiz (inklusive Abstand).
    func height(at index: Int) -> CGFloat {
        ColumnsGrid.stripHeight + model(at: index).contentHeight + EmbedOverlays.gap
    }

    /// Wo liegt dieser Spalten-Editor?
    func position(of controller: EditorController) -> (block: Int, column: Int)? {
        for (block, model) in models.enumerated() {
            if let column = model.columns.firstIndex(where: { $0.controller === controller }) {
                return (block, column)
            }
        }
        return nil
    }

    var controllers: [EditorController] {
        models.flatMap { $0.columns.map(\.controller) }
    }

    fileprivate func changed(_ model: ColumnBlockModel) {
        onChange(model.index, ColumnBlock(columns: model.columns.map(\.text)))
    }

    fileprivate func dissolve(_ model: ColumnBlockModel) {
        onDissolve(model.index)
    }

    fileprivate func heightChanged() {
        onLayoutChange()
    }
}

@Observable
@MainActor
final class ColumnBlockModel {
    let index: Int
    @ObservationIgnored private weak var owner: NoteColumns?
    private(set) var columns: [ColumnModel] = []
    /// So hoch wie die längste Spalte.
    private(set) var contentHeight = ColumnBlockModel.minimumHeight

    private static let minimumHeight: CGFloat = 60

    init(index: Int, owner: NoteColumns) {
        self.index = index
        self.owner = owner
    }

    func update(_ texts: [String]) {
        let shrinks = columns.count > texts.count
        while columns.count > texts.count {
            owner?.owner?.columnRemoved(columns.removeLast().controller)
        }
        while columns.count < texts.count {
            let column = ColumnModel(parent: owner?.owner)
            column.controller.onContentHeight = { [weak self, weak column] height in
                guard let self, let column else { return }
                column.height = height
                self.updateHeight()
            }
            columns.append(column)
        }
        for (column, text) in zip(columns, texts) where column.text != text {
            column.text = text
            column.controller.setText(text)
        }
        if shrinks { updateHeight() }
    }

    func setText(_ text: String, ofColumn index: Int) {
        guard columns.indices.contains(index), columns[index].text != text else { return }
        columns[index].text = text
        owner?.changed(self)
    }

    /// Spalten einfügen, verschieben oder löschen.
    func edit(_ change: (inout ColumnBlock) -> Void) {
        var block = ColumnBlock(columns: columns.map(\.text))
        change(&block)
        update(block.columns)
        owner?.changed(self)
    }

    func dissolve() {
        owner?.dissolve(self)
    }

    private func updateHeight() {
        let height = max(Self.minimumHeight, columns.map(\.height).max() ?? 0)
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        owner?.heightChanged()
    }
}

@Observable
@MainActor
final class ColumnModel: Identifiable {
    var text = ""
    var height: CGFloat = 0
    @ObservationIgnored let controller: EditorController

    init(parent: EditorController?) {
        controller = EditorController(parent: parent)
    }
}

/// Die Spalten eines Bereichs nebeneinander. Über jeder Spalte ein kleines
/// Menü. Auf schmalen Bildschirmen lässt sich der Bereich seitwärts schieben.
struct ColumnsGrid: View {
    let model: ColumnBlockModel

    static let stripHeight: CGFloat = 20
    static let minimumWidth: CGFloat = 150

    var body: some View {
        GeometryReader { geometry in
            let count = max(model.columns.count, 1)
            let width = max(Self.minimumWidth, geometry.size.width / CGFloat(count))
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(model.columns.indices, id: \.self) { index in
                            menu(index, count: count)
                                .frame(width: width, height: Self.stripHeight)
                        }
                    }
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(model.columns.enumerated()), id: \.element.id) { index, column in
                            editor(column, index: index)
                                .frame(width: width, height: model.contentHeight)
                                .overlay(alignment: .trailing) {
                                    if index < count - 1 {
                                        Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1)
                                    }
                                }
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.35)))
                }
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(width * CGFloat(count) <= geometry.size.width + 1)
        }
    }

    private func editor(_ column: ColumnModel, index: Int) -> some View {
        MarkdownTextView(
            text: Binding(get: { column.text }, set: { model.setText($0, ofColumn: index) }),
            controller: column.controller,
            embedded: true
        )
        .overlay(alignment: .topLeading) {
            if column.text.isEmpty {
                Text("Spalte \(index + 1)")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, MarkdownTextView.embeddedInset)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
            }
        }
    }

    private func menu(_ column: Int, count: Int) -> some View {
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
            Divider()
            Button("Spalten auflösen", systemImage: "text.alignleft") { model.dissolve() }
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
}
