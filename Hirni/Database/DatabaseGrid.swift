import HirniKit
import SwiftUI

/// Tabelle mit allen sichtbaren Spalten, waagrecht scrollbar, Werte direkt in
/// den Zellen bearbeiten. Vorne die Zeilennummer: Antippen öffnet das
/// Formular, ihr Menü (lange drücken bzw. Rechtsklick) bietet Seite und Löschen.
///
/// Verwendet auf dem iPhone für die Tabellen-Ansicht und überall für
/// eingebettete Tabellen in Notizen. Die volle Mac-Tabelle hat zusätzlich
/// Mehrfachauswahl und Tastenkürzel.
struct DatabaseGrid: View {
    let document: DatabaseDocument
    /// Eingebettet: höchstens so viele Einträge, nur waagrecht scrollen.
    var limit: Int?
    let open: (String) -> Void
    let openPage: PageOpener

    static let headerHeight: CGFloat = 30
    static let groupHeight: CGFloat = 30
    #if os(iOS)
    static let rowHeight: CGFloat = 44
    #else
    static let rowHeight: CGFloat = 32
    #endif
    static let handleWidth: CGFloat = 40

    var body: some View {
        let fields = document.visibleFields
        if let limit {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    header(fields)
                    rows(Self.groups(of: document, limit: limit), fields: fields)
                    footer(fields)
                }
            }
            .defaultScrollAnchor(.topLeading, for: .alignment)
        } else {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        rows(document.result.groups, fields: fields)
                        footer(fields)
                    } header: {
                        header(fields)
                    }
                }
                .padding(.bottom, 20)
            }
            .defaultScrollAnchor(.topLeading, for: .alignment)
        }
    }

    /// Eine Zeile des Rasters: Gruppenkopf oder Eintrag mit fortlaufender Nummer.
    private enum Line: Identifiable {
        case group(id: String, title: String, count: Int)
        case row(Row, number: Int)

        var id: String {
            switch self {
            case .group(let id, _, _): "gruppe|" + id
            case .row(let row, _): row.id
            }
        }
    }

    private func rows(_ groups: [QueryResult.Group], fields: [Field]) -> some View {
        var lines: [Line] = []
        var number = 0
        for group in groups {
            if let title = group.title {
                let count = document.result.groups.first { $0.id == group.id }?.rows.count ?? group.rows.count
                lines.append(.group(id: group.id, title: title, count: count))
            }
            for row in group.rows {
                number += 1
                lines.append(.row(row, number: number))
            }
        }
        return ForEach(lines) { line in
            switch line {
            case .group(_, let title, let count): groupHeader(title, count: count)
            case .row(let row, let number): rowView(row, number: number, fields: fields)
            }
        }
    }

    /// Die Gruppen, gekürzt auf die ersten `limit` Einträge (für eingebettete Tabellen).
    static func groups(of document: DatabaseDocument, limit: Int) -> [QueryResult.Group] {
        var left = limit
        var result: [QueryResult.Group] = []
        for group in document.result.groups where left > 0 {
            let rows = Array(group.rows.prefix(left))
            left -= rows.count
            result.append(.init(id: group.id, title: group.title, rows: rows))
        }
        return result
    }

    /// Höhe der eingebetteten Tabelle.
    static func embeddedHeight(of document: DatabaseDocument, limit: Int) -> CGFloat {
        let groups = groups(of: document, limit: limit)
        let rows = groups.reduce(0) { $0 + $1.rows.count }
        let titles = groups.filter { $0.title != nil }.count
        let footer = (document.currentView.aggregates ?? [:]).isEmpty ? 0 : headerHeight
        return headerHeight + CGFloat(rows) * rowHeight + CGFloat(titles) * groupHeight + footer + 14
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
        .frame(height: Self.groupHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06))
    }

    private func rowView(_ row: Row, number: Int, fields: [Field]) -> some View {
        HStack(spacing: 0) {
            handle(row, number: number)
            ForEach(fields) { field in
                CellEditor(field: field, raw: binding(row: row.id, field: field.name), compact: true)
                    .padding(.horizontal, 8)
                    .frame(width: Self.width(of: field), height: Self.rowHeight, alignment: field.type.isNumeric ? .trailing : .leading)
                Divider()
            }
        }
        .frame(height: Self.rowHeight)
        .background(number.isMultiple(of: 2) ? Color.primary.opacity(0.03) : .clear)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    /// Zeilennummer (und Seiten-Symbol): Antippen öffnet das Formular.
    private func handle(_ row: Row, number: Int) -> some View {
        Menu {
            Button("Formular öffnen", systemImage: "list.bullet.rectangle") { open(row.id) }
            PageButton(document: document, rowID: row.id, open: openPage)
            Divider()
            Button("Eintrag löschen", systemImage: "trash", role: .destructive) { document.deleteRows([row.id]) }
        } label: {
            HStack(spacing: 2) {
                Text("\(number)").font(.caption.monospacedDigit())
                if document.rowPages[row.id] != nil {
                    Image(systemName: "doc.text").font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
            .frame(width: Self.handleWidth, height: Self.rowHeight)
            .contentShape(Rectangle())
        } primaryAction: {
            open(row.id)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        #if os(macOS)
        .menuIndicator(.hidden)
        .help("Klicken: Formular · Gedrückt halten: Seite, Löschen")
        #endif
    }

    private func binding(row id: String, field: String) -> Binding<String> {
        Binding(
            get: { document.value(row: id, field: field) },
            set: { document.setValue($0, row: id, field: field) }
        )
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
                    .frame(width: Self.width(of: field), alignment: field.type.isNumeric ? .trailing : .leading)
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
        case .text, .url: 160
        case .multiSelect: 140
        case .date: (field.includesTime ?? false) ? 210 : 140
        case .checkbox: 64
        case .number, .select, .formula: 115
        }
        #else
        switch field.type {
        case .text, .url: 200
        case .multiSelect: 160
        case .date: (field.includesTime ?? false) ? 190 : 150
        case .checkbox: 80
        case .number, .select, .formula: 130
        }
        #endif
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
