import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// Eigener Typ für Drag'n'Drop innerhalb von hirni (deklariert in Config/Info.plist).
    nonisolated static let hirniItem = UTType(exportedAs: "ch.hebera.hirni.item")
}

/// Was beim Ziehen einer Notiz oder eines Ordners mitgegeben wird.
///
/// Bewusst keine Datei-URL: Sonst könnte man eine Notiz aus Versehen auf den
/// Schreibtisch ziehen, und der Finder würde sie aus iCloud herausverschieben.
nonisolated struct VaultItemTransfer: Codable, Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .hirniItem)
    }
}
