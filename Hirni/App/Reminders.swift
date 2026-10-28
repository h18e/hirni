import HirniKit
import UserNotifications

/// Plant die Mitteilungen am Stichtag von Pendenzen (siehe `TaskReminders`)
/// und öffnet beim Antippen die Notiz.
///
/// Jedes Gerät plant für sich; mit iCloud kommen die Stichtage überall an.
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()

    private var planned: [TaskReminder]?
    /// Angetippte Notiz, bevor die App bereit war.
    private var pendingOpen: String?
    /// Öffnet eine Notiz (Pfad ab dem Hirni-Ordner).
    var onOpen: ((String) -> Void)? {
        didSet {
            if let pendingOpen, let onOpen {
                self.pendingOpen = nil
                onOpen(pendingOpen)
            }
        }
    }

    /// Früh setzen, damit auch ein Antippen bei geschlossener App ankommt.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Fragt einmal nach der Erlaubnis für Mitteilungen (danach entscheidet
    /// die Einstellung des Systems).
    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func update(_ plan: [TaskReminder]) async {
        guard plan != planned else { return }
        planned = plan
        let center = UNUserNotificationCenter.current()
        if !plan.isEmpty { await requestPermission() }
        let old = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(TaskReminders.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.userInfo = ["note": reminder.notePath]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let request = UNNotificationRequest(
                identifier: reminder.id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            try? await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let path = response.notification.request.content.userInfo["note"] as? String else { return }
        await MainActor.run {
            if let onOpen { onOpen(path) } else { pendingOpen = path }
        }
    }
}
