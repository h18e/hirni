import Foundation

/// Eine Mitteilung am Stichtag einer offenen Pendenz.
public struct TaskReminder: Equatable, Sendable {
    /// Stabil pro Pendenz (Notiz und Text), damit neu Planen alte ersetzt.
    public let id: String
    public let date: Date
    public let title: String
    public let body: String
    /// Notiz, Pfad ab dem Hirni-Ordner (zum Öffnen beim Antippen).
    public let notePath: String
}

public enum TaskReminders {
    public static let identifierPrefix = "pendenz|"
    /// iOS behält höchstens 64 geplante Mitteilungen pro App.
    public static let limit = 60

    /// Mitteilungen für alle offenen Pendenzen mit Stichtag, um `hour` Uhr am
    /// Stichtag. Vergangene Zeitpunkte fallen weg, die nächsten zuerst.
    public static func plan(
        tasks: [TaskItem], dueDates: TaskDueDates, in vault: Vault,
        now: Date = .now, hour: Int = 9, calendar: Calendar = .current
    ) -> [TaskReminder] {
        var seen = Set<String>()
        var result: [TaskReminder] = []
        for task in tasks where !task.isDone {
            let key = task.dueKey(in: vault)
            guard seen.insert(key).inserted, let due = dueDates.due(for: key) else { continue }
            // Das Datum ist ohne Zeitzone gespeichert: Tag übernehmen, Uhrzeit setzen.
            var day = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: due)
            day.hour = hour
            guard let date = calendar.date(from: day), date > now else { continue }
            result.append(TaskReminder(
                id: identifierPrefix + key,
                date: date,
                title: task.text,
                body: "Heute fällig · \(Vault.title(of: task.note))",
                notePath: vault.relativePath(of: task.note) ?? task.note.lastPathComponent
            ))
        }
        return Array(result.sorted { $0.date < $1.date }.prefix(limit))
    }
}
