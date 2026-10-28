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

    @Test func stampsOnlyFilledTasks() {
        #expect(TaskLine.stamped("- [ ] Milch", now: now) == "- [ ] Milch ➕ 2026-10-28")
        #expect(TaskLine.stamped("- [ ] ", now: now) == "- [ ] ")
        #expect(TaskLine.stamped("- [ ] Milch ➕ 2026-01-01", now: now) == "- [ ] Milch ➕ 2026-01-01")
        #expect(TaskLine.stamped("- [x] Brot ✅ 2026-10-27", now: now) == "- [x] Brot ➕ 2026-10-28 ✅ 2026-10-27")
        #expect(TaskLine.stamped("Text", now: now) == "Text")
        let text = "- [ ] A\n- [ ] B\n```\n- [ ] Code\n```"
        #expect(TaskLine.stampAll(text, skippingLine: 1, now: now) == "- [ ] A ➕ 2026-10-28\n- [ ] B\n```\n- [ ] Code\n```")
    }

    @Test func categoryReplacesFirstTag() {
        #expect(TaskLine.setCategory("büro", line: "- [ ] Steuern ➕ 2026-10-20") == "- [ ] Steuern #büro ➕ 2026-10-20")
        #expect(TaskLine.setCategory("privat", line: "- [ ] Steuern #büro #wichtig") == "- [ ] Steuern #privat #wichtig")
        #expect(TaskLine.setCategory(nil, line: "- [ ] Steuern #büro ➕ 2026-10-20") == "- [ ] Steuern ➕ 2026-10-20")
        #expect(TaskLine.setCategory("Haus Garten", line: "- [ ] Rasen") == "- [ ] Rasen #Haus-Garten")
    }

    @Test func findsTasksAndUpdatesLine() throws {
        let test = try TestVault()
        try test.write("---\nangepinnt: true\n---\n# Liste\n- [ ] Milch #einkauf ➕ 2026-10-20\n- [x] Brot ✅ 2026-10-27\n- [ ] \n- normal", to: "Inbox/Einkauf.md")
        try test.write("- [ ] Vorlage", to: "Vorlagen/V.md")
        let tasks = test.vault.allTasks()
        #expect(tasks.map(\.text) == ["Milch #einkauf", "Brot"])
        #expect(tasks[0].line == 4 && tasks[0].category == "einkauf" && !tasks[0].isDone)
        #expect(TaskLine.format(tasks[0].created!) == "2026-10-20")
        #expect(tasks[1].isDone && TaskLine.format(tasks[1].done!) == "2026-10-27")
        #expect(tasks[1].created != nil) // Erstelldatum der Notiz

        try test.vault.updateTask(tasks[0]) { TaskLine.setDone(true, line: $0, now: now) }
        #expect(try test.vault.readNote(at: tasks[0].note).contains("- [x] Milch #einkauf ➕ 2026-10-20 ✅ 2026-10-28"))
        // Zeile inzwischen anders: Fehler statt falsche Zeile ändern
        #expect(throws: TaskError.self) { try test.vault.updateTask(tasks[0]) { $0 } }
    }
}
