import Foundation

/// Regeln für Datei- und Ordnernamen. In hirni gilt: Dateiname = Titel.
public enum FileNaming {
    public static let untitled = "Ohne Titel"
    private static let maxLength = 200

    /// Macht aus einem frei eingegebenen Titel einen gültigen Dateinamen
    /// (ohne Endung). `/` und `:` sind in Dateinamen auf Apple-Systemen nicht
    /// erlaubt, ein führender Punkt würde die Datei verstecken.
    public static func sanitized(_ title: String) -> String {
        var name = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.count > maxLength { name = String(name.prefix(maxLength)) }
        return name.isEmpty ? untitled : name
    }

    /// Liefert `folder/baseName.ext`, oder `baseName 2.ext`, `baseName 3.ext` …,
    /// falls der Name schon belegt ist. `excluding` wird nicht als belegt gezählt
    /// (beim Umbenennen die Datei selbst).
    public static func uniqueURL(
        in folder: URL,
        baseName: String,
        pathExtension: String?,
        excluding: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        func candidate(_ number: Int) -> URL {
            let name = number == 1 ? baseName : "\(baseName) \(number)"
            let file = pathExtension.map { "\(name).\($0)" } ?? name
            return folder.appending(path: file, directoryHint: pathExtension == nil ? .isDirectory : .notDirectory)
        }
        var number = 1
        while true {
            let url = candidate(number)
            if let excluding, url.lastPathComponent.lowercased() == excluding.lastPathComponent.lowercased() {
                return url
            }
            if !exists(url, fileManager: fileManager) { return url }
            number += 1
        }
    }

    /// Prüft auch auf iCloud-Platzhalter, die noch nicht heruntergeladen sind.
    static func exists(_ url: URL, fileManager: FileManager) -> Bool {
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) { return true }
        let placeholder = url.deletingLastPathComponent()
            .appending(path: ICloudPlaceholder.placeholderName(for: url.lastPathComponent))
        return fileManager.fileExists(atPath: placeholder.path(percentEncoded: false))
    }
}

/// iCloud legt für noch nicht heruntergeladene Dateien versteckte Platzhalter
/// an: aus `Notiz.md` wird `.Notiz.md.icloud`.
public enum ICloudPlaceholder {
    public static func realName(forPlaceholder name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > ".icloud".count + 1 else {
            return nil
        }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    public static func placeholderName(for name: String) -> String {
        ".\(name).icloud"
    }
}
