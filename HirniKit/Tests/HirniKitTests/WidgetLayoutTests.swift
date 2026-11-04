import Foundation
import Testing
@testable import HirniKit

struct WidgetLayoutTests {
    func snapshot(_ categories: [String?]) -> WidgetSnapshot {
        let items = categories.enumerated().map { index, category in
            WidgetSnapshot.Item(id: "\(index)", text: "P\(index)", note: "N", notePath: "n.md", due: nil, category: category)
        }
        return WidgetSnapshot(openCount: items.count, items: items)
    }

    func ids(_ page: [WidgetLine]) -> [String] { page.map(\.id) }

    @Test func splitsIntoPagesAndRepeatsHeader() {
        let pages = WidgetLayout.pages(snapshot(["a", "a", "a", "b", nil]), display: WidgetDisplay(), budget: 3.6)
        #expect(pages.map(ids) == [["#a", "0", "1", "2"], ["#b", "3", "#", "4"]])
        let tight = WidgetLayout.pages(snapshot(["a", "a", "a"]), display: WidgetDisplay(), budget: 2.6)
        #expect(tight.map(ids) == [["#a", "0", "1"], ["#a", "2"]])
    }

    @Test func headerStaysWithItsFirstItem() {
        let pages = WidgetLayout.pages(snapshot(["a", "a", "b"]), display: WidgetDisplay(), budget: 3)
        #expect(pages.map(ids) == [["#a", "0", "1"], ["#b", "2"]])
    }

    @Test func collapsedCategoriesShowOnlyHeaderWithCount() {
        var display = WidgetDisplay()
        display.toggle("A")
        display.toggle(nil)
        let pages = WidgetLayout.pages(snapshot(["a", "a", "b", nil]), display: display, budget: 3.6)
        #expect(pages == [[
            .header(category: "a", count: 2, collapsed: true),
            .header(category: "b", count: 1, collapsed: false),
            .item(snapshot(["a", "a", "b", nil]).items[2]),
            .header(category: nil, count: 1, collapsed: true),
        ]])
        display.toggle("a")
        #expect(display.collapsed == [""])
    }

    @Test func emptySnapshotAndFile() throws {
        #expect(WidgetLayout.pages(WidgetSnapshot(), display: WidgetDisplay(), budget: 3).isEmpty)
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(WidgetDisplay.load(from: folder) == WidgetDisplay())
        var display = WidgetDisplay()
        display.toggle("büro")
        display.page = 2
        try display.save(to: folder)
        #expect(WidgetDisplay.load(from: folder) == display)
    }
}
