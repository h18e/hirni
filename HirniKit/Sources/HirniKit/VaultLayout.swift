import Foundation

/// Feste Namen und Regeln für den Aufbau des hirni-Ordners in iCloud Drive.
///
/// ```
/// hirni/
/// ├── Inbox/                ← neue Notizen landen hier
/// ├── Vorlagen/            ← Vorlagen für neue Notizen und Seiten
/// ├── <eigene Ordner>/
/// │   └── _Anhänge/         ← Bilder und Dateien der Notizen in diesem Ordner
/// └── _Zuletzt gelöscht/
/// ```
///
/// Siehe docs/spec.md, Abschnitt «Datenmodell».
public enum VaultLayout {
    public static let inboxFolderName = "Inbox"
    public static let trashFolderName = "_Zuletzt gelöscht"
    public static let attachmentsFolderName = "_Anhänge"
    /// Vorlagen für neue Notizen und Zeilen-Seiten. Ein normaler, sichtbarer
    /// Ordner: Vorlagen werden wie Notizen angelegt und bearbeitet.
    public static let templatesFolderName = "Vorlagen"

    public static let noteExtension = "md"
    public static let databaseSuffix = ".hirnidb.md"

    /// Systemordner beginnen mit `_` (von hirni verwaltet) oder `.` (versteckt,
    /// z. B. `.obsidian` oder `.Trash`). Sie erscheinen nicht in der Ordnerliste.
    public static func isSystemFolder(named name: String) -> Bool {
        name.hasPrefix("_") || name.hasPrefix(".")
    }

    /// Ordner, die beim ersten Start angelegt werden, falls sie fehlen.
    public static let requiredFolders = [inboxFolderName, trashFolderName, templatesFolderName]

    /// Legt die nötigen Ordner unter `root` an. Bestehende Inhalte bleiben unberührt.
    public static func prepare(root: URL, fileManager: FileManager = .default) throws {
        for name in requiredFolders {
            let folder = root.appending(path: name, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }
}
