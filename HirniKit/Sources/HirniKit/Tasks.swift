import Foundation

/// Eine Pendenz: eine Checkbox-Zeile (`- [ ] …`) in einer Notiz.
///
/// Die Daten stehen in der Zeile selbst, wie beim Obsidian-Plugin «Tasks»:
///
/// ```
/// - [ ] Steuererklärung #büro ➕ 2026-10-28
/// - [x] Velo flicken ➕ 2026-10-20 ✅ 2026-10-27
/// ```
///
/// `➕` = erfasst, `✅` = erledigt. Die Kategorie ist der erste Tag der Zeile.
public struct TaskItem: Identifiable, Hashable, Sendable {
    /// Notiz und Zeile, z. B. `Inbox/Einkauf.md#3`.
    public var id: String { "\(note.path(percentEncoded: false))#\(line)" }
    public let note: URL
    /// Zeilennummer in der Datei (ab 0, inklusive YAML-Kopf).
    public let line: Int
    /// Text ohne Marker und Daten, Tags bleiben stehen.
    public let text: String
    /// Die ganze Zeile, um vor dem Ändern zu prüfen, ob sie noch gleich ist.
    public let rawLine: String
    public let isDone: Bool
    /// Aus `➕`, sonst das Erstelldatum der Notiz.
    public let created: Date?
    public let done: Date?
    /// Erster Tag der Zeile (ohne `#`), `nil` = ohne Kategorie.
    public let category: String?
}

public enum TaskLine {
    static let createdMark = "➕"
    static let doneMark = "✅"
    static let checkbox = try! NSRegularExpression(pattern: #"^(\s*[-*+][ \t]+)\[([ xX])\](?=[ \t]|$)"#)
    static let datePattern = try! NSRegularExpression(pattern: #"[ \t]*(➕|✅)[ \t]*(\d{4}-\d{2}-\d{2})"#)

    /// `yyyy-MM-dd` in der Zeitzone des Geräts.
    public static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// Ist die Zeile eine Checkbox? Liefert erledigt ja/nein.
    public static func state(of line: String) -> Bool? {
        let ns = line as NSString
        guard let m = checkbox.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 2)) != " "
    }

    /// Der Inhalt hinter `[ ]`, ohne Daten.
    static func content(of line: String) -> String {
        let ns = line as NSString
        guard let m = checkbox.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return line }
        let rest = ns.substring(from: NSMaxRange(m.range))
        return datePattern.stringByReplacingMatches(in: rest, range: NSRange(location: 0, length: (rest as NSString).length), withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
    }

    static func date(_ mark: String, in line: String) -> Date? {
        let ns = line as NSString
        for m in datePattern.matches(in: line, range: NSRange(location: 0, length: ns.length))
        where ns.substring(with: m.range(at: 1)) == mark {
            return parseDate(ns.substring(with: m.range(at: 2)))
        }
        return nil
    }

    static func removing(_ mark: String, from line: String) -> String {
        let ns = line as NSString
        var result = line
        for m in datePattern.matches(in: line, range: NSRange(location: 0, length: ns.length)).reversed()
        where ns.substring(with: m.range(at: 1)) == mark {
            result = (result as NSString).replacingCharacters(in: m.range, with: "")
        }
        return result
    }

    /// Abhaken bzw. wieder öffnen: `[x]` und `✅ Datum` setzen oder entfernen.
    public static func setDone(_ done: Bool, line: String, now: Date = .now) -> String {
        let ns = line as NSString
        guard let m = checkbox.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return line }
        var result = ns.replacingCharacters(in: m.range(at: 2), with: done ? "x" : " ")
        result = removing(doneMark, from: result)
        if done {
            result = result.trimmingTrailingWhitespace() + " \(doneMark) \(format(now))"
        }
        return result
    }

    /// Erfasst-Datum anfügen, falls es fehlt und die Pendenz schon Text hat.
    public static func stamped(_ line: String, now: Date = .now) -> String {
        guard state(of: line) != nil, date(createdMark, in: line) == nil, !content(of: line).isEmpty else { return line }
        // Vor einem allfälligen ✅, damit die Reihenfolge stimmt.
        let ns = line as NSString
        if let done = datePattern.matches(in: line, range: NSRange(location: 0, length: ns.length))
            .first(where: { ns.substring(with: $0.range(at: 1)) == doneMark }) {
            return ns.replacingCharacters(in: NSRange(location: done.range.location, length: 0), with: " \(createdMark) \(format(now))")
        }
        return line.trimmingTrailingWhitespace() + " \(createdMark) \(format(now))"
    }

    /// Kategorie setzen: ersten Tag der Zeile ersetzen, sonst vor den Daten
    /// einfügen. `nil` entfernt den ersten Tag.
    public static func setCategory(_ category: String?, line: String) -> String {
        let ns = line as NSString
        guard let box = checkbox.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return line }
        let body = NSRange(NSMaxRange(box.range)..<ns.length)
        let firstTag = MarkdownSyntax.spans(in: line).first { span in
            if case .tag = span.kind { return span.range.location >= body.location } else { return false }
        }
        let tag = category.map { "#" + $0.replacingOccurrences(of: " ", with: "-") }
        if let firstTag {
            var range = firstTag.range
            if tag == nil, range.location > 0, ns.character(at: range.location - 1) == 0x20 { range = NSRange(location: range.location - 1, length: range.length + 1) }
            return ns.replacingCharacters(in: range, with: tag ?? "")
        }
        guard let tag else { return line }
        let insertAt = datePattern.firstMatch(in: line, range: body)?.range.location ?? ns.length
        let before = ns.substring(to: insertAt).trimmingTrailingWhitespace()
        return before + " " + tag + ns.substring(from: insertAt)
    }

    /// Alle Pendenzen eines Notiztexts (Codeblöcke zählen nicht).
    static func tasks(in text: String, note: URL, fallbackCreated: Date?) -> [TaskItem] {
        var result: [TaskItem] = []
        var inFence = false
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle(); continue }
            guard !inFence, let done = state(of: line) else { continue }
            let content = content(of: line)
            guard !content.isEmpty else { continue }
            result.append(TaskItem(
                note: note, line: index, text: content, rawLine: line, isDone: done,
                created: date(createdMark, in: line) ?? fallbackCreated,
                done: date(doneMark, in: line),
                category: MarkdownSyntax.tags(in: content).first
            ))
        }
        return result
    }

    /// Fehlende Erfasst-Daten in allen Pendenzen ergänzen, ausser in der
    /// Zeile `skippingLine` (dort wird gerade getippt).
    public static func stampAll(_ text: String, skippingLine: Int? = nil, now: Date = .now) -> String {
        var lines = text.components(separatedBy: "\n")
        var inFence = false
        for index in lines.indices {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle(); continue }
            guard !inFence, index != skippingLine else { continue }
            lines[index] = stamped(lines[index], now: now)
        }
        return lines.joined(separator: "\n")
    }
}

extension String {
    func trimmingTrailingWhitespace() -> String {
        var s = self
        while let last = s.last, last == " " || last == "\t" { s.removeLast() }
        return s
    }
}

public enum TaskError: LocalizedError {
    case changed

    public var errorDescription: String? {
        "Die Pendenz wurde inzwischen in der Notiz geändert. Die Liste ist jetzt aktualisiert, bitte nochmals versuchen."
    }
}

extension Vault {
    /// Alle Pendenzen im Hirni-Ordner, ohne Vorlagen.
    public func allTasks() -> [TaskItem] {
        allNoteURLs()
            .filter { !$0.isInside(templatesURL) }
            .flatMap { url -> [TaskItem] in
                guard let text = try? String(contentsOf: url, encoding: .utf8), text.contains("[") else { return [] }
                let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
                return TaskLine.tasks(in: text, note: url, fallbackCreated: created)
            }
    }

    /// Die Pendenzen einer einzelnen Notiz.
    public func allTasks(in note: URL) -> [TaskItem] {
        guard let text = try? readNote(at: note) else { return [] }
        let created = try? note.resourceValues(forKeys: [.creationDateKey]).creationDate
        return TaskLine.tasks(in: text, note: note, fallbackCreated: created)
    }

    /// Ändert die Zeile einer Pendenz. Ist sie inzwischen anders, passiert nichts.
    public func updateTask(_ task: TaskItem, _ change: (String) -> String) throws {
        let text = try readNote(at: task.note)
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(task.line), lines[task.line] == task.rawLine else { throw TaskError.changed }
        lines[task.line] = change(lines[task.line])
        try writeNote(lines.joined(separator: "\n"), to: task.note)
    }
}
