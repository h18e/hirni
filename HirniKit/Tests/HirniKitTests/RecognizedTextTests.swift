import CoreGraphics
import HirniKit
import Testing

struct RecognizedTextTests {
    /// Zeile `index` von oben, 3 % hoch, mit wenig Abstand.
    private func line(_ text: String, row: Double, width: Double = 0.8, x: Double = 0.1) -> RecognizedText.Line {
        RecognizedText.Line(text: text, box: CGRect(x: x, y: 0.9 - row * 0.035, width: width, height: 0.03))
    }

    @Test func joinsLinesOfAParagraph() {
        let text = RecognizedText.compose([
            line("Das ist ein langer Absatz, der über", row: 0),
            line("mehrere Zeilen geht und zusammen-", row: 1),
            line("gehört.", row: 2, width: 0.2),
        ])
        #expect(text == "Das ist ein langer Absatz, der über mehrere Zeilen geht und zusammengehört.")
    }

    @Test func largeGapsSeparateParagraphs() {
        let text = RecognizedText.compose([
            line("Erster Absatz endet hier und ist lang genug", row: 0),
            line("Zweiter Absatz nach einer Lücke", row: 2),
        ])
        #expect(text == "Erster Absatz endet hier und ist lang genug\n\nZweiter Absatz nach einer Lücke")
    }

    @Test func bulletsBecomeListItems() {
        let text = RecognizedText.compose([
            line("Einkauf:", row: 0, width: 0.2),
            line("• Milch", row: 1, width: 0.2),
            line("• Brot", row: 2, width: 0.2),
        ])
        #expect(text == "Einkauf:\n- Milch\n- Brot")
    }

    @Test func shortLinesStaySeparate() {
        let text = RecognizedText.compose([
            line("Hans Muster", row: 0, width: 0.3),
            line("Bahnhofstrasse 1", row: 1, width: 0.3),
            line("8000 Zürich", row: 2, width: 0.3),
        ])
        #expect(text == "Hans Muster\nBahnhofstrasse 1\n8000 Zürich")
    }

    @Test func emptyInputGivesEmptyText() {
        #expect(RecognizedText.compose([]) == "")
    }

    @Test func recognizedNoteUsesFirstLineAsTitle() {
        let note = SharedItem.recognizedNote(from: "Rezept\n\nMehl und Wasser mischen.")
        #expect(note.title == "Rezept")
        #expect(note.text == "Mehl und Wasser mischen.\n")
        let long = SharedItem.recognizedNote(from: String(repeating: "Wort ", count: 20))
        #expect(long.title.hasSuffix("…"))
        #expect(long.text.hasPrefix("Wort Wort"))
    }
}
