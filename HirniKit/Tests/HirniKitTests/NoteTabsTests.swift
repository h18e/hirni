import Foundation
import Testing
@testable import HirniKit

struct NoteTabsTests {
    private func note(_ name: String) -> URL { URL(filePath: "/hirni/\(name).md") }

    @Test func openingAddsEachNoteOnce() {
        var tabs = NoteTabs()
        tabs.open(note("a"))
        tabs.open(note("b"))
        tabs.open(note("a"))
        #expect(tabs.urls == [note("a"), note("b")])
    }

    @Test func oldestTabFallsAwayAtTheLimit() {
        var tabs = NoteTabs()
        for number in 0...NoteTabs.limit { tabs.open(note("\(number)")) }
        #expect(tabs.urls.count == NoteTabs.limit)
        #expect(tabs.urls.first == note("1"))
        #expect(tabs.urls.last == note("\(NoteTabs.limit)"))
    }

    @Test func closingReturnsTheNeighbour() {
        var tabs = NoteTabs(urls: [note("a"), note("b"), note("c")])
        #expect(tabs.close(note("b")) == note("c"))
        #expect(tabs.close(note("c")) == note("a"))
        #expect(tabs.close(note("a")) == nil)
        #expect(tabs.urls.isEmpty)
    }

    @Test func renameKeepsThePlace() {
        var tabs = NoteTabs(urls: [note("a"), note("b")])
        tabs.replace(note("a"), with: note("neu"))
        #expect(tabs.urls == [note("neu"), note("b")])
    }

    @Test func retainDropsMissingFiles() {
        var tabs = NoteTabs(urls: [note("a"), note("b")])
        tabs.retain { $0 == note("b") }
        #expect(tabs.urls == [note("b")])
    }
}
