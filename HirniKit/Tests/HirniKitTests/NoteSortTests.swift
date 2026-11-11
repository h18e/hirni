import Foundation
import HirniKit
import Testing

struct NoteSortTests {
    private func note(_ title: String, modified: Double, created: Double, pinned: Bool = false) -> NoteSummary {
        NoteSummary(
            url: URL(filePath: "/tmp/\(title).md"), title: title,
            modified: Date(timeIntervalSince1970: modified), created: Date(timeIntervalSince1970: created),
            preview: "", isDownloaded: true, isPinned: pinned
        )
    }

    private var notes: [NoteSummary] {
        [note("banane", modified: 3, created: 1), note("Apfel", modified: 1, created: 3), note("Zitrone", modified: 2, created: 2)]
    }

    @Test func sortsByTitleIgnoringCase() {
        #expect(NoteSort(field: .title, ascending: true).apply(notes).map(\.title) == ["Apfel", "banane", "Zitrone"])
        #expect(NoteSort(field: .title, ascending: false).apply(notes).map(\.title) == ["Zitrone", "banane", "Apfel"])
    }

    @Test func sortsByCreationDate() {
        #expect(NoteSort(field: .created, ascending: false).apply(notes).map(\.title) == ["Apfel", "Zitrone", "banane"])
        #expect(NoteSort(field: .created, ascending: true).apply(notes).map(\.title) == ["banane", "Zitrone", "Apfel"])
    }

    @Test func defaultIsNewestChangeFirst() {
        #expect(NoteSort().apply(notes).map(\.title) == ["banane", "Zitrone", "Apfel"])
    }

    @Test func pinnedNotesStayOnTop() {
        let list = notes + [note("Mitte", modified: 0, created: 0, pinned: true)]
        #expect(NoteSort(field: .title, ascending: false).apply(list).first?.title == "Mitte")
        #expect(NoteSort(field: .created, ascending: true).apply(list).first?.title == "Mitte")
    }

    @Test func naturalOrderDependsOnField() {
        #expect(NoteSort.natural(.title).ascending)
        #expect(!NoteSort.natural(.created).ascending)
    }
}
