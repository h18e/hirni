import Foundation

/// Feste Namen und Regeln für den Aufbau des hirni-Ordners in iCloud Drive.
///
/// ```
/// hirni/
/// ├── Inbox/                ← neue Notizen landen hier
/// ├── Vorlagen/            ← Vorlagen für neue Notizen und Seiten (auch `00 Vorlagen`)
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

    /// Vorlagen-Ordner: `Vorlagen`, auch mit Nummer davor zum Sortieren
    /// (`00 Vorlagen`, `00_Vorlagen`), Gross/klein egal.
    public static func isTemplatesFolder(named name: String) -> Bool {
        name.range(of: #"^(\d+[\s_.\-]*)?\#(templatesFolderName)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Der Vorlagen-Ordner unter `root`. Ein umbenannter geht dem Standardnamen
    /// vor; `nil`, wenn es noch keinen gibt.
    public static func templatesFolder(in root: URL, fileManager: FileManager = .default) -> URL? {
        let names = (try? fileManager.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        let matches = names.filter(isTemplatesFolder(named:)).sorted()
        guard let name = matches.first(where: { $0 != templatesFolderName }) ?? matches.first else { return nil }
        return root.appending(path: name, directoryHint: .isDirectory)
    }

    /// Legt die nötigen Ordner unter `root` an. Bestehende Inhalte bleiben
    /// unberührt. Wurde der Vorlagen-Ordner umbenannt, entsteht kein zweiter;
    /// ein leerer `Vorlagen` daneben (von früher) wird entfernt.
    public static func prepare(root: URL, fileManager: FileManager = .default) throws {
        let templates = templatesFolder(in: root, fileManager: fileManager)
        for name in requiredFolders where !(name == templatesFolderName && templates != nil) {
            let folder = root.appending(path: name, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let standard = root.appending(path: templatesFolderName, directoryHint: .isDirectory)
        if let templates, templates.lastPathComponent != templatesFolderName,
           let content = try? fileManager.contentsOfDirectory(atPath: standard.path(percentEncoded: false)),
           content.allSatisfy({ $0.hasPrefix(".") }) {
            try? fileManager.removeItem(at: standard)
        }
    }
}
