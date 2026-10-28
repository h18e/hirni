import Foundation
import Testing
@testable import HirniKit

struct TaskRemindersTests {
    @Test func plansOpenTasksWithDueDate() throws {
        let test = try TestVault()
        try test.write("- [ ] Steuern #büro\n- [x] Velo ✅ 2026-10-01\n- [ ] Ohne Datum\n- [ ] Vorbei\n", to: "Inbox/Liste.md")
        let tasks = test.vault.allTasks()
        var dates = TaskDueDates()
        for task in tasks {
            let key = task.dueKey(in: test.vault)
            switch task.text {
            case "Steuern #büro": dates.stichtage[key] = "2026-11-03"
            case "Velo": dates.stichtage[key] = "2026-11-04"
            case "Vorbei": dates.stichtage[key] = "2026-10-20"
            default: break
            }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12))!

        let plan = TaskReminders.plan(tasks: tasks, dueDates: dates, in: test.vault, now: now, hour: 9, calendar: calendar)
        #expect(plan.count == 1)
        let reminder = try #require(plan.first)
        #expect(reminder.title == "Steuern #büro")
        #expect(reminder.body == "Heute fällig · Liste")
        #expect(reminder.notePath == "Inbox/Liste.md")
        #expect(reminder.id == "pendenz|Inbox/Liste.md|Steuern #büro")
        #expect(calendar.dateComponents([.year, .month, .day, .hour], from: reminder.date)
            == DateComponents(year: 2026, month: 11, day: 3, hour: 9))
    }

    @Test func skipsTodayAfterReminderHour() throws {
        let test = try TestVault()
        try test.write("- [ ] Heute\n", to: "Inbox/A.md")
        let tasks = test.vault.allTasks()
        var dates = TaskDueDates()
        dates.stichtage[tasks[0].dueKey(in: test.vault)] = "2026-10-28"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 7))!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12))!
        #expect(TaskReminders.plan(tasks: tasks, dueDates: dates, in: test.vault, now: morning, calendar: calendar).count == 1)
        #expect(TaskReminders.plan(tasks: tasks, dueDates: dates, in: test.vault, now: noon, calendar: calendar).isEmpty)
    }
}

struct TaskDeleteTests {
    @Test func deletesLineAndDueDate() throws {
        let test = try TestVault()
        try test.write("# Liste\n- [ ] Milch\n- [x] Velo ✅ 2026-10-01\nEnde\n", to: "Inbox/Liste.md")
        let milch = try #require(test.vault.allTasks().first { $0.text == "Milch" })
        var dates = TaskDueDates()
        dates.stichtage[milch.dueKey(in: test.vault)] = "2026-11-03"
        dates.stichtage["Inbox/Andere.md|X"] = "2026-11-04"
        try test.vault.saveDueDates(dates)

        try test.vault.deleteTask(milch)
        let text = try test.vault.readNote(at: milch.note)
        #expect(text == "# Liste\n- [x] Velo ✅ 2026-10-01\nEnde\n")
        #expect(test.vault.dueDates().stichtage == ["Inbox/Andere.md|X": "2026-11-04"])
        // Zweites Mal: Zeile stimmt nicht mehr.
        #expect(throws: TaskError.self) { try test.vault.deleteTask(milch) }
    }
}
