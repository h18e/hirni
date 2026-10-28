import EventKit
import HirniKit
import os

/// Überträgt Termine aus Datenbanken in einen eigenen Kalender «Hirni» im
/// Apple Kalender (siehe `CalendarSync`). Nur in diese Richtung: Hirni ist die
/// Quelle, Änderungen im Kalender werden beim nächsten Abgleich überschrieben.
///
/// Der Kalender liegt wenn möglich in iCloud; dann sehen ihn alle Geräte.
/// Jedes Gerät gleicht ab; doppelte Termine räumt der Abgleich weg.
final class CalendarExporter {
    static let shared = CalendarExporter()
    nonisolated static let calendarTitle = "Hirni"
    private static let calendarIDKey = "kalenderID"

    private let store = EKEventStore()
    private let log = Logger(subsystem: "ch.hebera.hirni", category: "kalender")
    private var running = false
    private var lastWanted: [CalendarItem]?

    /// Gleicht ab, wenn sich an den Terminen etwas geändert hat. Fragt nur
    /// dann nach dem Zugriff, wenn eine Datenbank im Kalender erscheinen soll.
    func sync(_ vault: Vault, force: Bool = false) async {
        guard !running else { return }
        running = true
        defer { running = false }
        let wanted = await Task.detached { CalendarSync.items(in: vault) }.value
        guard force || wanted != lastWanted else { return }

        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            guard !wanted.isEmpty else { lastWanted = wanted; return }
            guard (try? await store.requestFullAccessToEvents()) == true else { lastWanted = wanted; return }
        } else if status != .fullAccess {
            lastWanted = wanted
            return
        }
        guard let calendar = calendar(create: !wanted.isEmpty) else { lastWanted = wanted; return }

        // Weiter Zeitraum: Termine liegen selten mehr als ein paar Jahre weg.
        let now = Date.now
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-3 * 365 * 86_400),
            end: now.addingTimeInterval(10 * 365 * 86_400),
            calendars: [calendar]
        )
        let events = store.events(matching: predicate)
        let existing = events.map { event in
            ExistingCalendarEvent(id: event.calendarItemIdentifier, item: event.url.map {
                CalendarItem(url: $0, title: event.title ?? "", start: event.startDate, end: event.endDate,
                             isAllDay: event.isAllDay, notes: event.notes ?? "")
            })
        }
        let plan = CalendarSync.plan(existing: existing, wanted: wanted)
        let byID = Dictionary(events.map { ($0.calendarItemIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        do {
            for id in plan.delete { if let event = byID[id] { try store.remove(event, span: .thisEvent, commit: false) } }
            for (id, item) in plan.update {
                guard let event = byID[id] else { continue }
                apply(item, to: event)
                try store.save(event, span: .thisEvent, commit: false)
            }
            for item in plan.create {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                apply(item, to: event)
                try store.save(event, span: .thisEvent, commit: false)
            }
            if !plan.isEmpty { try store.commit() }
            lastWanted = wanted
            log.debug("Kalender: \(plan.create.count) neu, \(plan.update.count) geändert, \(plan.delete.count) entfernt")
        } catch {
            store.reset()
            log.error("Kalender: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ item: CalendarItem, to event: EKEvent) {
        event.title = item.title
        event.startDate = item.start
        event.endDate = item.end
        event.isAllDay = item.isAllDay
        event.notes = item.notes
        event.url = item.url
    }

    /// Der eigene Kalender «Hirni»: gemerkt, sonst nach Name gesucht (z. B.
    /// vom anderen Gerät über iCloud angelegt), sonst neu.
    private func calendar(create: Bool) -> EKCalendar? {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: Self.calendarIDKey), let calendar = store.calendar(withIdentifier: id) {
            return calendar
        }
        if let calendar = store.calendars(for: .event).first(where: { $0.title == Self.calendarTitle && $0.allowsContentModifications }) {
            defaults.set(calendar.calendarIdentifier, forKey: Self.calendarIDKey)
            return calendar
        }
        guard create else { return nil }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.calendarTitle
        calendar.cgColor = CGColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1)
        let sources = store.sources
        calendar.source = sources.first { $0.sourceType == .calDAV && $0.title == "iCloud" }
            ?? store.defaultCalendarForNewEvents?.source
            ?? sources.first { $0.sourceType == .local }
        do {
            try store.saveCalendar(calendar, commit: true)
            defaults.set(calendar.calendarIdentifier, forKey: Self.calendarIDKey)
            return calendar
        } catch {
            log.error("Kalender anlegen: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
