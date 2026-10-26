import HirniKit
import SwiftUI

/// Tabelle zum Ansehen: alle sichtbaren Spalten nebeneinander, waagrecht
/// scrollbar. Ein Tipp auf eine Zeile öffnet das Formular.
///
/// Verwendet auf dem iPhone für die Tabellen-Ansicht und überall für
/// eingebettete Tabellen in Notizen. Am Mac hat die volle Datenbank ein
/// eigenes Raster, in dem man direkt in den Zellen tippt.
struct DatabaseGrid: View {
    let document: DatabaseDocument
    /// Eingebettet: nur die ersten Einträge, ohne Gruppen, nur waagrecht scrollen.
    var limit: Int?
    let open: (String) -> Void

    static let headerHeight: CGFloat = 30
    #if os(iOS)
    static let rowHeight: CGFloat = 44
    #else
    static let rowHeight: CGFloat = 32
    #endif
    static let handleWidth: CGFloat = 30

    var body: some View {
        let fields = document.visibleFields
        if limit == nil {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(document.result.groups) { group in
                            if let title = group.title { groupHeader(title, count: group.rows.count) }
                            ForEach(group.rows) { row in rowView(row, fields: fields) }
                        }
                        footer(fields)
                    } header: {
                        header(fields)
                    }
                }
                .padding(.bottom, 20)
            }
            .defaultScrollAnchor(.topLeading, for: .alignment)
        } else {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    header(fields)
                    ForEach(document.result.rows.prefix(limit ?? 0)) { row in rowView(row, fields: fields) }
                    footer(fields)
                }
            }
            .defaultScrollAnchor(.topLeading, for: .alignment)
        }
    }

    /// Überschriften lassen sich ziehen (iPhone: lange drücken), um Spalten
    /// zu verschieben. Ganz rechts abgelegt kommt die Spalte ans Ende.
    private func header(_ fields: [Field]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.handleWidth)
            ForEach(fields) { field in
                ColumnHeader(field: field, width: Self.width(of: field), height: Self.headerHeight) { dragged in
                    document.moveField(dragged, before: field.name)
                }
                Divider()
            }
            Color.clear
                .frame(width: 60)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { names, _ in
                    guard let name = names.first, document.database.field(named: name) != nil else { return false }
                    document.moveField(name, before: nil)
                    return true
                }
        }
        .frame(height: Self.headerHeight)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func groupHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline.bold())
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.leading, Self.handleWidth + 8)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06))
    }

    private func rowView(_ row: Row, fields: [Field]) -> some View {
        Button { open(row.id) } label: {
            HStack(spacing: 0) {
                Group {
                    if document.rowPages[row.id] != nil {
                        Image(systemName: "doc.text").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: Self.handleWidth)
                ForEach(fields) { field in
                    CellText(field: field, raw: row[field.name])
                        .padding(.horizontal, 8)
                        .frame(width: Self.width(of: field), height: Self.rowHeight, alignment: field.type == .number ? .trailing : .leading)
                    Divider()
                }
            }
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    /// Berechnungen unter den Spalten, über alle passenden Einträge.
    @ViewBuilder
    private func footer(_ fields: [Field]) -> some View {
        let aggregates = document.currentView.aggregates ?? [:]
        if !aggregates.isEmpty {
            let rows = document.result.rows
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.handleWidth)
                ForEach(fields) { field in
                    Group {
                        if let aggregate = aggregates[field.name] {
                            HStack(spacing: 4) {
                                Text(aggregate.label).foregroundStyle(.secondary)
                                Text(DatabaseQuery.display(aggregate, field: field, rows: rows)).bold()
                            }
                        } else {
                            Color.clear
                        }
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(width: Self.width(of: field), alignment: field.type == .number ? .trailing : .leading)
                    Divider()
                }
            }
            .frame(height: Self.headerHeight)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    /// Spaltenbreite je Feldtyp, auf dem iPhone schmaler.
    static func width(of field: Field) -> CGFloat {
        #if os(iOS)
        switch field.type {
        case .text, .url: 150
        case .multiSelect: 130
        case .date: (field.includesTime ?? false) ? 150 : 115
        case .checkbox: 64
        case .number, .select: 105
        }
        #else
        switch field.type {
        case .text, .url: 200
        case .multiSelect: 160
        case .date: (field.includesTime ?? false) ? 170 : 130
        case .checkbox: 80
        case .number, .select: 120
        }
        #endif
    }

    /// Höhe der eingebetteten Tabelle mit `rows` Einträgen.
    static func embeddedHeight(rows: Int, hasFooter: Bool) -> CGFloat {
        headerHeight + CGFloat(rows) * rowHeight + (hasFooter ? headerHeight : 0) + 12
    }
}

/// Ein Zellwert zum Lesen: Checkbox als Symbol, sonst der formatierte Text.
private struct CellText: View {
    let field: Field
    let raw: String

    var body: some View {
        switch field.type {
        case .checkbox:
            Image(systemName: CellValue.bool(raw) ? "checkmark.square.fill" : "square")
                .foregroundStyle(CellValue.bool(raw) ? Color.accentColor : .secondary)
        case .select where !raw.isEmpty:
            Text(raw)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.2), in: Capsule())
        default:
            Text(CellValue.display(raw, for: field))
                .font(.subheadline)
                .lineLimit(1)
                .foregroundStyle(field.type == .url ? Color.accentColor : .primary)
        }
    }

    private var color: Color {
        OptionColors.color(field.options?.firstIndex(of: raw))
    }
}

/// Eine Spaltenüberschrift, die sich ziehen lässt und gezogene Spalten annimmt.
struct ColumnHeader: View {
    let field: Field
    let width: CGFloat
    var height: CGFloat = 28
    let drop: (String) -> Void
    @State private var isTargeted = false

    var body: some View {
        Label(field.name, systemImage: field.type.systemImage)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(width: width, height: height, alignment: .leading)
            .contentShape(Rectangle())
            // Einfügemarke links: Hier landet die gezogene Spalte.
            .overlay(alignment: .leading) {
                if isTargeted { Rectangle().fill(Color.accentColor).frame(width: 3) }
            }
            .draggable(field.name) {
                Label(field.name, systemImage: field.type.systemImage)
                    .font(.caption.bold())
                    .padding(6)
                    .background(.bar, in: RoundedRectangle(cornerRadius: 6))
            }
            .dropDestination(for: String.self) { names, _ in
                guard let name = names.first, name != field.name else { return false }
                drop(name)
                return true
            } isTargeted: { isTargeted = $0 }
            #if os(macOS)
            .help("Ziehen, um die Spalte zu verschieben")
            #endif
    }
}
