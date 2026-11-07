import Foundation
import Testing
@testable import HirniKit

struct NoteTabsTests {
    private func note(_ name: String) -> URL { URL(filePath: "/hirni/\(name).md") }

    @Test func normalOpeningReplacesTheActiveTab() {
        var tabs = NoteTabs()
        tabs.show(note("a"))
        tabs.show(note("b"))
        tabs.show(note("c"))
        #expect(tabs.urls == [note("c")])
    }

    @Test func newTabKeepsTheOthers() {
        var tabs = NoteTabs()
        tabs.show(note("a"))
        tabs.openNew(note("b"))
        #expect(tabs.urls == [note("a"), note("b")])
        #expect(tabs.active == note("b"))
        tabs.show(note("c"))
        #expect(tabs.urls == [note("a"), note("c")])
    }

    @Test func openNoteWithATabJumpsThere() {
        var tabs = NoteTabs(urls: [note("a"), note("b")], active: note("b"))
        tabs.show(note("a"))
        #expect(tabs.urls == [note("a"), note("b")])
        #expect(tabs.active == note("a"))
        tabs.openNew(note("b"))
        #expect(tabs.urls == [note("a"), note("b")])
        #expect(tabs.active == note("b"))
    }

    @Test func closingReturnsTheNeighbour() {
        var tabs = NoteTabs(urls: [note("a"), note("b"), note("c")], active: note("b"))
        #expect(tabs.close(note("b")) == note("c"))
        #expect(tabs.active == note("c"))
        #expect(tabs.close(note("c")) == note("a"))
        #expect(tabs.close(note("a")) == nil)
        #expect(tabs.urls.isEmpty)
        #expect(tabs.active == nil)
    }

    @Test func closingAnInactiveTabKeepsTheActiveOne() {
        var tabs = NoteTabs(urls: [note("a"), note("b")], active: note("b"))
        tabs.close(note("a"))
        #expect(tabs.active == note("b"))
    }

    @Test func renameKeepsThePlace() {
        var tabs = NoteTabs(urls: [note("a"), note("b")], active: note("a"))
        tabs.replace(note("a"), with: note("neu"))
        #expect(tabs.urls == [note("neu"), note("b")])
        #expect(tabs.active == note("neu"))
    }

    @Test func retainDropsMissingFiles() {
        var tabs = NoteTabs(urls: [note("a"), note("b")], active: note("a"))
        tabs.retain { $0 == note("b") }
        #expect(tabs.urls == [note("b")])
        #expect(tabs.active == note("b"))
    }
}
