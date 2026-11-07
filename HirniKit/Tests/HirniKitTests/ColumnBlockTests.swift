import Foundation
import Testing
@testable import HirniKit

struct ColumnBlockTests {
    private let sample = """
    Davor

    :::spalten
    - Eins
    - Zwei

    :::spalte
    | A | B |
    |---|---|
    | 1 | 2 |
    :::

    Danach
    """

    @Test func findsColumnsAndRanges() throws {
        let block = try #require(ColumnBlock.blocks(in: sample).first)
        #expect(block.columns == ["- Eins\n- Zwei\n", "| A | B |\n|---|---|\n| 1 | 2 |"])
        let ns = sample as NSString
        #expect(ns.substring(with: block.range).hasPrefix(":::spalten"))
        #expect(ns.substring(with: block.range).hasSuffix("| 1 | 2 |\n:::"))
        #expect(ns.substring(with: block.columnRanges[0]) == block.columns[0])
    }

    @Test func markdownRoundTrip() throws {
        let block = try #require(ColumnBlock.blocks(in: sample).first)
        #expect(block.markdown == (sample as NSString).substring(with: block.range))
    }

    @Test func emptyColumnsSurviveARoundTrip() throws {
        let markdown = ColumnBlock.empty(columns: 3).markdown
        let block = try #require(ColumnBlock.blocks(in: markdown).first)
        #expect(block.columns == ["", "", ""])
        #expect(block.markdown == markdown)
    }

    @Test func unclosedBlockIsPlainText() {
        #expect(ColumnBlock.blocks(in: ":::spalten\nText\n:::spalte\nMehr").isEmpty)
    }

    @Test func blockInCodeFenceDoesNotCount() {
        #expect(ColumnBlock.blocks(in: "```\n:::spalten\na\n:::\n```").isEmpty)
    }

    @Test func severalBlocksStayApart() {
        let text = ":::spalten\na\n:::\n\nMitte\n\n:::spalten\nb\n:::spalte\nc\n:::"
        #expect(ColumnBlock.blocks(in: text).map(\.columns) == [["a"], ["b", "c"]])
    }

    @Test func tablesAndDatabasesInColumnsBelongToTheColumn() {
        let text = ":::spalten\n| A |\n|---|\n:::spalte\n```hirni-db\ndatenbank: X\n```\n:::\n\n| B |\n|---|\n"
        #expect(MarkdownTable.tables(in: text).map(\.rows) == [[["B"]]])
        #expect(DatabaseEmbed.blocks(in: text).isEmpty)
    }

    @Test func columnAtLocation() throws {
        let block = try #require(ColumnBlock.blocks(in: sample).first)
        let second = block.columnRanges[1].location + 2
        #expect(block.column(at: second)?.index == 1)
        #expect(block.column(at: second)?.offset == 2)
        #expect(block.column(at: block.range.location) == nil)
    }

    @Test func editingColumns() {
        var block = ColumnBlock(columns: ["a", "b"])
        block.insertColumn(at: 1)
        #expect(block.columns == ["a", "", "b"])
        block.moveColumn(from: 2, to: 0)
        #expect(block.columns == ["b", "a", ""])
        block.removeColumn(at: 0)
        #expect(block.columns == ["a", ""])
        block.removeColumn(at: 1)
        block.removeColumn(at: 0)
        #expect(block.columns == ["a"])
    }

    @Test func dissolvingKeepsTheText() {
        #expect(ColumnBlock(columns: ["a", "", "b"]).dissolved == "a\n\nb")
    }

    @Test func htmlShowsColumnsSideBySide() {
        let html = NoteHTML.page(title: "T", markdown: sample)
        #expect(html.contains("<div class=\"columns\">"))
        #expect(!html.contains(":::"))
        #expect(html.contains("Danach"))
    }

    @Test func previewHidesTheMarks() {
        #expect(!NotePreview.make(from: sample).contains(":::"))
    }
}
