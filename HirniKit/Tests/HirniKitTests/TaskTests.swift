import Foundation
import Testing
@testable import HirniKit

struct TaskTests {
    let now = ISO8601DateFormatter().date(from: "2026-10-28T10:00:00Z")!

    @Test func doneAddsAndRemovesDate() {
        let open = "- [ ] Steuern #büro ➕ 2026-10-20"
        let done = TaskLine.setDone(true, line: open, now: now)
        #expect(done == "- [x] Steuern #büro ➕ 2026-10-20 ✅ 2026-10-28")
        #expect(TaskLine.setDone(false, line: done, now: now) == open)
    }

    @Test func removesCreatedDates() {
        let text = "- [ ] Milch ➕ 2026-10-28\n- [x] Brot ➕ 2026-10-21 ✅ 2026-10-27\nText ➕ 2026-10-28\n```\n- [ ] Code ➕ 2026-10-28\n```"
        #expect(TaskLine.removingCreatedDates(text) == "- [ ] Milch\n- [x] Brot ✅ 2026-10-27\nText ➕ 2026-10-28\n```\n- [ ] Code ➕ 2026-10-28\n```")
    }

    @Test func dueDatesInOwnFile() throws {
        let test = try TestVault()
        try test.write("- [ ] Steuern", to: "Inbox/Büro.md")
        let task = try #require(test.vault.allTasks().first)
        #expect(task.dueKey(in: test.vault) == "Inbox/Büro.md|Steuern")
        var dates = test.vault.dueDates()
        dates.set(now, for: task.dueKey(in: test.vault))
        try test.vault.saveDueDates(dates)
        #expect(test.exists("_Hirni/Pendenzen.json"))
        #expect(TaskLine.format(try #require(test.vault.dueDates().due(for: task.dueKey(in: test.vault)))) == "2026-10-28")
        #expect(try test.vault.readNote(at: task.note) == "- [ ] Steuern")
        // Systemordner erscheint nicht in der Seitenleiste
        #expect(!(try test.vault.folderTree().map(\.name).contains("_Hirni")))
    }

    @Test func categoryReplacesFirstTag() {
        #expect(TaskLine.setCategory("büro", line: "- [ ] Steuern ➕ 2026-10-20") == "- [ ] Steuern #büro ➕ 2026-10-20")
        #expect(TaskLine.setCategory("privat", line: "- [ ] Steuern #büro #wichtig") == "- [ ] Steuern #privat #wichtig")
        #expect(TaskLine.setCategory(nil, line: "- [ ] Steuern #büro ➕ 2026-10-20") == "- [ ] Steuern ➕ 2026-10-20")
        #expect(TaskLine.setCategory("Haus Garten", line: "- [ ] Rasen") == "- [ ] Rasen #Haus-Garten")
    }

    @Test func findsTasksAndUpdatesLine() throws {
        let test = try TestVault()
        try test.write("---\nangepinnt: true\n---\n# Liste\n- [ ] Milch #einkauf\n- [x] Brot ✅ 2026-10-27\n- [ ] \n- normal", to: "Inbox/Einkauf.md")
        try test.write("- [ ] Vorlage", to: "Vorlagen/V.md")
        let tasks = test.vault.allTasks()
        #expect(tasks.map(\.text) == ["Milch #einkauf", "Brot"])
        #expect(tasks[0].line == 4 && tasks[0].category == "einkauf" && !tasks[0].isDone)
        #expect(tasks[1].isDone && TaskLine.format(tasks[1].done!) == "2026-10-27")

        try test.vault.updateTask(tasks[0]) { TaskLine.setDone(true, line: $0, now: now) }
        #expect(try test.vault.readNote(at: tasks[0].note).contains("- [x] Milch #einkauf ✅ 2026-10-28"))
        // Zeile inzwischen anders: Fehler statt falsche Zeile ändern
        #expect(throws: TaskError.self) { try test.vault.updateTask(tasks[0]) { $0 } }
    }
}
