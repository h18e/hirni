import Foundation
import Testing
@testable import HirniKit

struct MarkdownTableTests {
    @Test func findsTablesAndIgnoresCode() {
        let text = "Vorher\n| Was | Wann |\n|---|:--:|\n| Zoo | Sa |\n| A \\| B | x<br>y |\nNachher\n```\n| a | b |\n|---|---|\n```"
        let tables = MarkdownTable.tables(in: text)
        #expect(tables.count == 1)
        #expect(tables[0].rows == [["Was", "Wann"], ["Zoo", "Sa"], ["A | B", "x\ny"]])
        #expect((text as NSString).substring(with: tables[0].range).hasSuffix("x<br>y |"))
    }

    @Test func roundTripAndPadding() {
        let table = MarkdownTable(rows: [["A", "B"], ["1"]])
        #expect(table.markdown == "| A | B |\n|---|---|\n| 1 |  |")
        #expect(MarkdownTable.tables(in: table.markdown).first?.rows == [["A", "B"], ["1", ""]])
        #expect(MarkdownTable(rows: [["a|b"], ["x\ny"]]).markdown == "| a\\|b |\n|---|\n| x<br>y |")
    }

    @Test func previewShowsCells() {
        #expect(NotePreview.make(from: "Liste:\n| Was | Wer |\n|---|---|\n| Zelt | Papa |") == "Liste: Was · Wer Zelt · Papa")
    }

    @Test func notATableWithoutSeparator() {
        #expect(MarkdownTable.tables(in: "| nur | eine Zeile |\n| und noch eine |").isEmpty)
    }

    @Test func insertRemoveMove() {
        var table = MarkdownTable.empty()
        #expect(table.rows == [["Spalte 1", "Spalte 2", "Spalte 3"], ["", "", ""], ["", "", ""]])
        table.rows[1][0] = "x"
        table.insertColumn(at: 0)
        #expect(table.rows[0] == ["Spalte 4", "Spalte 1", "Spalte 2", "Spalte 3"])
        table.moveColumn(from: 0, to: 3)
        #expect(table.rows[1] == ["x", "", "", ""])
        table.removeColumn(at: 3)
        table.insertRow(at: 1)
        #expect(table.rows[2][0] == "x" && table.rows.count == 4)
        table.moveRow(from: 2, to: 1)
        #expect(table.rows[1][0] == "x")
        table.removeRow(at: 0) // Kopf bleibt
        #expect(table.rows.count == 4)
    }

    @Test func resizeOnlyRemovesEmptyTrailing() {
        var table = MarkdownTable.empty(columns: 2, rows: 1)
        table.resize(columns: 4, bodyRows: 3)
        #expect(table.columnCount == 4 && table.rows.count == 4)
        table.rows[3][3] = "voll"
        table.resize(columns: 1, bodyRows: 1)
        #expect(table.columnCount == 4 && table.rows.count == 4) // letzte Zeile/Spalte nicht leer
        table.rows[3][3] = ""
        table.resize(columns: 1, bodyRows: 1)
        #expect(table.columnCount == 1 && table.rows.count == 2)
    }
}
