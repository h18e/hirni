import HirniKit
import SwiftUI

/// Zeilen-Seite öffnen bzw. anlegen. Gibt es Vorlagen und noch keine Seite,
/// fragt ein Menü: leer oder aus welcher Vorlage.
typealias PageOpener = (_ rowID: String, _ template: URL?) -> Void

struct PageButton: View {
    @Environment(VaultStore.self) private var store
    let document: DatabaseDocument
    let rowID: String
    let open: PageOpener

    var body: some View {
        if document.rowPages[rowID] != nil {
            Button("Seite öffnen", systemImage: "doc.text") { open(rowID, nil) }
        } else if store.templates.isEmpty {
            Button("Seite anlegen", systemImage: "doc.badge.plus") { open(rowID, nil) }
        } else {
            Menu {
                Button("Leere Seite", systemImage: "doc") { open(rowID, nil) }
                Section("Vorlagen") {
                    ForEach(store.templates) { template in
                        Button(template.name, systemImage: "doc.text") { open(rowID, template.url) }
                    }
                }
            } label: {
                Label("Seite anlegen", systemImage: "doc.badge.plus")
            }
        }
    }
}
