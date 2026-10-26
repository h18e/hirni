import Foundation

/// Eine Vorlage: eine Notiz im Ordner «Vorlagen».
public struct NoteTemplate: Identifiable, Hashable, Sendable {
    public let url: URL
    public var id: URL { url }
    /// Name wie im Ordner, mit Platzhaltern (z. B. «Besprechung {{datum}}»).
    public var name: String { Vault.title(of: url) }
}

/// Füllt Platzhalter in Vorlagen aus.
///
/// - `{{datum}}` 26.10.2026, `{{iso-datum}}` 2026-10-26, `{{zeit}}` 14:30,
///   `{{wochentag}}` Montag, `{{titel}}` Titel der neuen Notiz
/// - bei Zeilen-Seiten zusätzlich `{{Feldname}}` mit dem Wert des Eintrags
///   (ein Feld «Datum» geht dabei `{{datum}}` vor)
///
/// Gross-/Kleinschreibung spielt keine Rolle, unbekannte Platzhalter bleiben stehen.
public enum TemplateFiller {
    public static func fill(_ text: String, title: String?, date: Date, values: [String: String] = [:]) -> String {
        var known = builtIns(date: date)
        // Felder des Eintrags gehen vor: Heisst ein Feld «Datum», meint
        // {{Datum}} auf einer Zeilen-Seite dessen Wert, nicht heute.
        for (key, value) in values { known[key.lowercased()] = value }
        if let title { known["titel"] = title }

        let pattern = try! NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(last..<match.range.location))
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            result += known[key] ?? ns.substring(with: match.range)
            last = NSMaxRange(match.range)
        }
        return result + ns.substring(from: last)
    }

    static func builtIns(date: Date) -> [String: String] {
        let locale = Locale(identifier: "de_CH")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        func format(_ pattern: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.dateFormat = pattern
            return formatter.string(from: date)
        }
        return [
            "datum": format("dd.MM.yyyy"),
            "iso-datum": format("yyyy-MM-dd"),
            "zeit": format("HH:mm"),
            "wochentag": format("EEEE"),
        ]
    }

    /// Text der Vorlage für eine neue Notiz: Platzhalter ausgefüllt,
    /// «angepinnt» und eine Zeilen-Zuordnung aus dem Kopf entfernt.
    public static func noteText(fromTemplate template: String, title: String, date: Date, values: [String: String] = [:]) -> String {
        var text = fill(template, title: title, date: date, values: values)
        text = Frontmatter.setting(Frontmatter.pinnedKey, to: nil, in: text)
        text = Frontmatter.setting(Vault.rowKey, to: nil, in: text)
        return text
    }
}

extension Vault {
    public var templatesURL: URL {
        root.appending(path: VaultLayout.templatesFolderName, directoryHint: .isDirectory)
    }

    /// Alle Vorlagen, alphabetisch. Datenbanken im Ordner zählen nicht.
    public func templates() -> [NoteTemplate] {
        ((try? entries(in: templatesURL)) ?? [])
            .filter { !$0.isDirectory && $0.isDownloaded && Self.isNote(name: $0.name) }
            .map { NoteTemplate(url: $0.url) }
    }

    /// Neue Notiz aus einer Vorlage. Der Titel kommt vom Namen der Vorlage,
    /// ebenfalls mit ausgefüllten Platzhaltern.
    public func createNote(in folder: URL, fromTemplate template: URL, now: Date = .now) throws -> URL {
        let title = TemplateFiller.fill(Self.title(of: template), title: nil, date: now)
        let text = TemplateFiller.noteText(fromTemplate: try readNote(at: template), title: title, date: now)
        return try createNote(in: folder, title: title, text: text)
    }
}
