import HirniKit
import SwiftUI

/// Ansicht «Liste»: eine Zeile pro Eintrag mit dem ersten Feld als Titel und
/// den nächsten Werten darunter, gruppiert wie die Ansicht. Unten die Berechnungen.
struct DatabaseRowList: View {
    let document: DatabaseDocument
    let open: (String) -> Void
    let openPage: PageOpener

    var body: some View {
        let result = document.result
        let fields = document.visibleFields
        List {
            ForEach(result.groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        Button { open(row.id) } label: {
                            RowSummary(fields: fields, row: row, hasPage: document.rowPages[row.id] != nil)
                        }
                        .tint(.primary)
                        .swipeActions {
                            Button("Löschen", systemImage: "trash", role: .destructive) {
                                document.deleteRows([row.id])
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Seite", systemImage: "doc.text") { openPage(row.id, nil) }
                                .tint(.blue)
                        }
                    }
                } header: {
                    if let title = group.title {
                        Text("\(title) · \(group.rows.count)")
                    }
                }
            }

            let aggregates = document.currentView.aggregates ?? [:]
            if !aggregates.isEmpty {
                Section("Berechnungen") {
                    ForEach(document.database.fields.filter { aggregates[$0.name] != nil }) { field in
                        if let aggregate = aggregates[field.name] {
                            LabeledContent("\(aggregate.label) \(field.name)") {
                                Text(DatabaseQuery.display(aggregate, field: field, rows: result.rows)).bold()
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if document.database.rows.isEmpty {
                ContentUnavailableView("Noch keine Einträge", systemImage: "tablecells", description: Text("Mit + oben einen Eintrag hinzufügen."))
            } else if result.rows.isEmpty {
                ContentUnavailableView("Keine passenden Einträge", systemImage: "line.3.horizontal.decrease", description: Text("Die Filter dieser Ansicht treffen auf keinen Eintrag zu."))
            }
        }
    }
}

/// Eine Zeile der Liste, auch für die eingebettete Liste in Notizen.
struct RowSummary: View {
    let fields: [Field]
    let row: Row
    let hasPage: Bool

    var body: some View {
        HStack {
            details
            if hasPage {
                Spacer()
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Hat eine Seite")
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            let first = fields.first.map { CellValue.display(row[$0.name], for: $0) } ?? ""
            Text(first.isEmpty ? "Ohne Namen" : first)
                .font(.headline)
                .foregroundStyle(first.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            let details = fields.dropFirst().prefix(3)
                .map { CellValue.display(row[$0.name], for: $0) }
                .filter { !$0.isEmpty }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
