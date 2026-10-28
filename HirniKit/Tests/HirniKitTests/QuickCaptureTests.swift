import Foundation
import Testing
@testable import HirniKit

struct QuickCaptureTests {
    @Test func quickNoteUsesFirstLine() throws {
        let test = try TestVault()
        let note = try test.vault.quickNote("Idee fürs Fest\nGrillieren am See")
        #expect(note.lastPathComponent == "Idee fürs Fest.md")
        #expect(try test.vault.readNote(at: note) == "Idee fürs Fest\nGrillieren am See\n")
    }

    @Test func quickTaskAppendsOrCreates() throws {
        let test = try TestVault()
        let first = try test.vault.quickTask("Milch kaufen")
        #expect(first.lastPathComponent == "Pendenzen.md")
        try test.vault.writeNote(try test.vault.readNote(at: first) + "Notiz ohne Zeilenende", to: first)
        try test.vault.quickTask("Velo\nflicken #haus")
        #expect(try test.vault.readNote(at: first) == "- [ ] Milch kaufen\nNotiz ohne Zeilenende\n- [ ] Velo flicken #haus\n")
        #expect(test.vault.allTasks().count == 2)
    }

    @Test func snapshotSortsByDueDate() throws {
        let test = try TestVault()
        try test.write("- [ ] A\n- [ ] B\n- [x] C\n- [ ] D\n", to: "Inbox/Liste.md")
        let tasks = test.vault.allTasks()
        var dates = TaskDueDates()
        dates.stichtage["Inbox/Liste.md|D"] = "2026-11-01"
        dates.stichtage["Inbox/Liste.md|B"] = "2026-11-05"
        let snapshot = WidgetSnapshot.make(tasks: tasks, dueDates: dates, in: test.vault, limit: 3)
        #expect(snapshot.openCount == 3)
        #expect(snapshot.items.map(\.text) == ["D", "B", "A"])
        #expect(snapshot.items[0].note == "Liste")
        #expect(snapshot.items[0].notePath == "Inbox/Liste.md")

        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try snapshot.save(to: folder)
        #expect(WidgetSnapshot.load(from: folder) == snapshot)
    }
}
