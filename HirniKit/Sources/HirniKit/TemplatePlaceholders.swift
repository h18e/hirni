import Foundation

/// Datumsangaben in Platzhaltern: `heute`, `morgen`, `übermorgen`, `gestern`,
/// `+7` / `-1` (Tage), `+2w` (Wochen), `+1m` (Monate), `montag` bzw.
/// `nächster montag` (nächster solcher Tag nach heute), `2026-11-03`, `03.11.2026`.
public enum DateExpression {
    static let weekdays = ["sonntag", "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag"]

    public static func resolve(_ expression: String, from date: Date, calendar: Calendar = .current) -> Date? {
        let text = expression.trimmingCharacters(in: .whitespaces).lowercased()
        let today = calendar.startOfDay(for: date)
        func add(_ component: Calendar.Component, _ value: Int) -> Date? {
            calendar.date(byAdding: component, value: value, to: today)
        }
        switch text {
        case "heute", "": return today
        case "morgen": return add(.day, 1)
        case "übermorgen", "uebermorgen": return add(.day, 2)
        case "gestern": return add(.day, -1)
        default: break
        }
        if let match = text.wholeMatch(of: /([+-])\s*(\d+)\s*([dwm]?)/) {
            let amount = (Int(match.2) ?? 0) * (match.1 == "-" ? -1 : 1)
            switch match.3 {
            case "w": return add(.day, amount * 7)
            case "m": return add(.month, amount)
            default: return add(.day, amount)
            }
        }
        let name = text.hasPrefix("nächster ") ? String(text.dropFirst(9)) : text.hasPrefix("naechster ") ? String(text.dropFirst(10)) : text
        if let index = weekdays.firstIndex(of: name.trimmingCharacters(in: .whitespaces)) {
            return calendar.nextDate(after: today, matching: DateComponents(weekday: index + 1), matchingPolicy: .nextTime)
        }
        for format in ["yyyy-MM-dd", "dd.MM.yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            formatter.isLenient = false
            if let parsed = formatter.date(from: text) { return parsed }
        }
        return nil
    }
}

/// Eine Rückfrage beim Anlegen aus einer Vorlage: `{{frage: Mit wem?}}` (freier
/// Text) oder `{{wahl: Arbeit|Privat}}` (Auswahl). Gleiche Fragen werden nur
/// einmal gestellt; die Antwort steht überall, wo sie vorkommt.
public struct TemplateQuestion: Hashable, Identifiable, Sendable {
    /// Der Platzhalter ohne Klammern, z. B. `frage: Mit wem?`; Schlüssel der Antwort.
    public let id: String
    public let prompt: String
    /// Leer = freier Text.
    public let options: [String]

    static let pattern = try! NSRegularExpression(pattern: #"\{\{\s*(frage|wahl)\s*:\s*([^{}]+?)\s*\}\}"#, options: .caseInsensitive)

    /// Alle Fragen in den Texten, in der Reihenfolge ihres ersten Auftretens.
    public static func all(in texts: [String]) -> [TemplateQuestion] {
        var seen = Set<String>()
        var result: [TemplateQuestion] = []
        for text in texts {
            let ns = text as NSString
            for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let kind = ns.substring(with: match.range(at: 1)).lowercased()
                let content = ns.substring(with: match.range(at: 2))
                let id = key(kind: kind, content: content)
                guard seen.insert(id).inserted else { continue }
                if kind == "wahl" {
                    let options = content.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    result.append(TemplateQuestion(id: id, prompt: "Auswahl", options: options))
                } else {
                    result.append(TemplateQuestion(id: id, prompt: content, options: []))
                }
            }
        }
        return result
    }

    static func key(kind: String, content: String) -> String {
        "\(kind.lowercased()): \(content.trimmingCharacters(in: .whitespaces))"
    }
}

/// Was beim Anlegen aus einer Vorlage sonst noch bekannt ist (siehe `Vault.buildFromTemplate`).
public struct TemplateContext: Sendable {
    public var date: Date
    public var title: String?
    /// Werte eines Datenbank-Eintrags (Zeilen-Seiten), `{{Feldname}}`.
    public var values: [String: String] = [:]
    /// Antworten auf `TemplateQuestion`, nach `id`.
    public var answers: [String: String] = [:]
    /// `{{nr}}`: laufende Nummer dieser Vorlage.
    public var number: Int?
    /// `{{vorherige}}`: zuletzt aus dieser Vorlage angelegte Notiz.
    public var previous: (title: String, path: String)?
    /// `{{pendenzen …}}`: offene Pendenzen (Text, Kategorie, Notiztitel, Pfad).
    public var openTasks: [(text: String, category: String?, note: String, path: String)] = []
    /// `{{termine heute}}` / `{{termine morgen}}`.
    public var events: [CalendarItem] = []

    public init(date: Date, title: String? = nil, values: [String: String] = [:], answers: [String: String] = [:]) {
        self.date = date
        self.title = title
        self.values = values
        self.answers = answers
    }
}

extension TemplateFiller {
    /// Beispieltext `{{? Thema}}`: bleibt in der Notiz stehen, bis man ihn
    /// überschreibt; der Editor zeigt nur «Thema», grau.
    public static let hintPattern = try! NSRegularExpression(pattern: #"\{\{\?\s*([^{}]*?)\s*\}\}"#)

    /// Text ohne Beispieltexte (für Vorschau, PDF).
    public static func removingHints(_ text: String) -> String {
        guard text.contains("{{?") else { return text }
        return hintPattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
    }

    /// Bereich des Beispieltexts (samt Klammern), in dem `index` liegt.
    public static func hintRange(containing index: Int, in text: String) -> NSRange? {
        guard text.contains("{{?") else { return nil }
        let ns = text as NSString
        return hintPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .first { index >= $0.range.location && index <= NSMaxRange($0.range) }?.range
    }

    /// Wert eines Platzhalters, `nil` = unbekannt (bleibt stehen).
    static func resolve(_ rawKey: String, context: TemplateContext, known: [String: String]) -> String? {
        let key = rawKey.trimmingCharacters(in: .whitespaces)
        let lower = key.lowercased()
        if let value = known[lower] { return value }
        if let match = TemplateQuestion.pattern.firstMatch(in: "{{\(key)}}", range: NSRange(location: 0, length: ("{{\(key)}}" as NSString).length)) {
            let ns = "{{\(key)}}" as NSString
            let id = TemplateQuestion.key(kind: ns.substring(with: match.range(at: 1)), content: ns.substring(with: match.range(at: 2)))
            return context.answers[id] ?? ""
        }
        switch lower {
        case "nr": return context.number.map(String.init)
        case "vorherige":
            guard let previous = context.previous else { return "–" }
            return "[\(previous.title)](\(link(to: previous.path)))"
        default: break
        }
        if lower == "pendenzen" || lower.hasPrefix("pendenzen ") {
            let filter = lower.dropFirst("pendenzen".count).trimmingCharacters(in: CharacterSet(charactersIn: " #"))
            let tasks = context.openTasks.filter { filter.isEmpty || $0.category?.lowercased() == filter }
            guard !tasks.isEmpty else { return "_Keine offenen Pendenzen_" }
            return tasks.map { "- \($0.text) · [\($0.note)](\(link(to: $0.path)))" }.joined(separator: "\n")
        }
        if lower == "termine" || lower.hasPrefix("termine ") {
            let dayText = lower.dropFirst("termine".count).trimmingCharacters(in: .whitespaces)
            guard let day = DateExpression.resolve(dayText.isEmpty ? "heute" : dayText, from: context.date) else { return nil }
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: day)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let events = context.events
                .filter { $0.start < end && $0.end >= start }
                .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
            guard !events.isEmpty else { return "_Keine Termine_" }
            return events.map { event in
                let time = event.isAllDay ? "ganztägig" : event.start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                return "- \(time): [\(event.title)](\(event.url.absoluteString))"
            }.joined(separator: "\n")
        }
        // Relative Daten: {{morgen}}, {{datum+7}}, {{iso-datum-1}}, {{nächster montag}}
        var expression = lower
        var format = "dd.MM.yyyy"
        if expression.hasPrefix("iso-datum") {
            expression = String(expression.dropFirst("iso-datum".count))
            format = "yyyy-MM-dd"
        } else if expression.hasPrefix("datum") {
            expression = String(expression.dropFirst("datum".count))
        }
        guard !expression.isEmpty else { return nil }
        guard let date = DateExpression.resolve(expression, from: context.date) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    static func link(to path: String) -> String {
        var parts = URLComponents()
        parts.scheme = "hirni"
        parts.host = "notiz"
        parts.queryItems = [URLQueryItem(name: "pfad", value: path)]
        return parts.url?.absoluteString ?? ""
    }
}

/// Ergebnis von `Vault.buildFromTemplate`.
public struct TemplateBuild: Equatable, Sendable {
    public var title: String
    /// Ganzer Text der neuen Notiz (mit Kopf).
    public var text: String
    /// `{{cursor}}`: Stelle im Text ohne Kopf (UTF-16), dort steht der Cursor.
    public var cursor: Int?
    /// `{{stichtag: …}}`: Zeilennummer (im ganzen Text) und Stichtag.
    public var dueDates: [Int: Date]
}

/// Was sich die Vorlagen merken: laufende Nummer und letzte Notiz pro
/// Vorlage, in `_Hirni/Vorlagen.json`.
struct TemplateState: Codable {
    struct Entry: Codable {
        var nr: Int?
        var letzte: String?
    }
    var vorlagen: [String: Entry] = [:]
}

extension Vault {
    var templateStateURL: URL {
        root.appending(path: "_Hirni", directoryHint: .isDirectory).appending(path: "Vorlagen.json")
    }

    func templateState() -> TemplateState {
        guard let data = try? Coordinated.read(templateStateURL, { try Data(contentsOf: $0) }),
              let state = try? JSONDecoder().decode(TemplateState.self, from: data) else { return TemplateState() }
        return state
    }

    func saveTemplateState(_ state: TemplateState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(at: templateStateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Coordinated.write(templateStateURL) { try data.write(to: $0, options: .atomic) }
    }

    /// Rückfragen einer Vorlage (im Namen und im Text).
    public func templateQuestions(_ template: URL) -> [TemplateQuestion] {
        TemplateQuestion.all(in: [Self.title(of: template), (try? readNote(at: template)) ?? ""])
    }

    /// Füllt eine Vorlage aus, ohne etwas zu speichern. `title` = `nil`: Titel
    /// aus dem Namen der Vorlage.
    public func buildFromTemplate(_ template: URL, title: String? = nil, values: [String: String] = [:],
                                  answers: [String: String] = [:], now: Date = .now) throws -> TemplateBuild {
        let source = try readNote(at: template)
        let name = Self.title(of: template)
        let everything = name + "\n" + source
        var context = TemplateContext(date: now, values: values, answers: answers)
        let key = relativePath(of: template) ?? template.lastPathComponent
        let state = templateState().vorlagen[key]
        if everything.range(of: "{{nr}}", options: .caseInsensitive) != nil { context.number = (state?.nr ?? 0) + 1 }
        if let path = state?.letzte, FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false)) {
            context.previous = (Self.title(of: root.appending(path: path)), path)
        }
        if everything.range(of: "{{pendenzen", options: .caseInsensitive) != nil {
            context.openTasks = allTasks().filter { !$0.isDone }.map {
                ($0.text, $0.category, Self.title(of: $0.note), relativePath(of: $0.note) ?? $0.note.lastPathComponent)
            }
        }
        if everything.range(of: "{{termine", options: .caseInsensitive) != nil {
            context.events = CalendarSync.items(in: self)
        }

        let finalTitle = title ?? TemplateFiller.fill(name, context: context)
        context.title = finalTitle
        var text = TemplateFiller.fill(source, context: context)
        text = Frontmatter.setting(Frontmatter.pinnedKey, to: nil, in: text)
        text = Frontmatter.setting(Self.rowKey, to: nil, in: text)

        // {{stichtag: …}} aus Pendenzen-Zeilen herausnehmen und merken.
        var dueDates: [Int: Date] = [:]
        let duePattern = try! NSRegularExpression(pattern: #"[ \t]*\{\{\s*stichtag\s*:\s*([^{}]+?)\s*\}\}"#, options: .caseInsensitive)
        var lines = text.components(separatedBy: "\n")
        for index in lines.indices {
            let line = lines[index] as NSString
            guard let match = duePattern.firstMatch(in: lines[index], range: NSRange(location: 0, length: line.length)) else { continue }
            if let date = DateExpression.resolve(line.substring(with: match.range(at: 1)), from: now) { dueDates[index] = date }
            lines[index] = duePattern.stringByReplacingMatches(in: lines[index], range: NSRange(location: 0, length: line.length), withTemplate: "")
        }
        text = lines.joined(separator: "\n")

        // {{cursor}}: Stelle im Text ohne Kopf merken, Platzhalter entfernen.
        let cursorPattern = try! NSRegularExpression(pattern: #"\{\{\s*cursor\s*\}\}"#, options: .caseInsensitive)
        let body = Frontmatter.split(text).body
        let cursor = cursorPattern.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length))?.range.location
        text = cursorPattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
        return TemplateBuild(title: finalTitle, text: text, cursor: cursor, dueDates: dueDates)
    }

    /// Neue Notiz aus einer Vorlage, mit Antworten auf die Rückfragen. Merkt
    /// sich Nummer und letzte Notiz der Vorlage und setzt die Stichtage.
    public func createNote(in folder: URL, fromTemplate template: URL, answers: [String: String], now: Date = .now) throws -> (url: URL, cursor: Int?) {
        let build = try buildFromTemplate(template, answers: answers, now: now)
        let url = try createNote(in: folder, title: build.title, text: build.text)
        try finishTemplateNote(url, build: build, template: template)
        return (url, build.cursor)
    }

    func finishTemplateNote(_ url: URL, build: TemplateBuild, template: URL) throws {
        if !build.dueDates.isEmpty {
            var dates = dueDates()
            for task in allTasks(in: url) {
                if let date = build.dueDates[task.line] { dates.set(date, for: task.dueKey(in: self)) }
            }
            try saveDueDates(dates)
        }
        let key = relativePath(of: template) ?? template.lastPathComponent
        var state = templateState()
        var entry = state.vorlagen[key] ?? .init()
        let source = (try? readNote(at: template)) ?? ""
        if (Self.title(of: template) + source).range(of: "{{nr}}", options: .caseInsensitive) != nil { entry.nr = (entry.nr ?? 0) + 1 }
        entry.letzte = relativePath(of: url)
        state.vorlagen[key] = entry
        try saveTemplateState(state)
    }
}
