import CoreGraphics
import Foundation

/// Macht aus den Zeilen der Texterkennung (Vision) einen Notiztext:
/// Zeilen eines Absatzes werden zusammengefügt, Trennstriche am Zeilenende
/// entfernt, Aufzählungen bleiben Listenpunkte, grössere Abstände trennen
/// Absätze.
public enum RecognizedText {
    public struct Line: Sendable, Equatable {
        public let text: String
        /// Normiert (0…1), Ursprung unten links wie bei Vision.
        public let box: CGRect

        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }
    }

    public static func compose(_ lines: [Line]) -> String {
        let lines = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return "" }
        let widest = lines.map(\.box.maxX).max() ?? 1
        var result = ""
        var previous: Line?
        for line in lines {
            let text = listItem(line.text.trimmingCharacters(in: .whitespaces))
            guard let prev = previous else {
                result = text
                previous = line
                continue
            }
            let height = max(prev.box.height, line.box.height, 0.001)
            let gap = prev.box.minY - line.box.maxY
            let wentUp = line.box.minY > prev.box.maxY  // nächste Spalte
            let prevText = result.components(separatedBy: "\n").last ?? ""
            if gap > height * 0.8 || wentUp {
                result += "\n\n" + text
            } else if prevText.hasSuffix("-"), text.first?.isLowercase == true {
                result.removeLast()
                result += text
            } else if text.hasPrefix("- ") || isListItem(prevText) && text.first?.isUppercase == true
                        || prev.box.maxX < widest * 0.8 || prev.box.width < 0.4 {
                // Neuer Listenpunkt oder kurze Zeile (Überschrift, Adresse …).
                result += "\n" + text
            } else {
                // Die Zeile reicht bis an den rechten Rand: Der Satz geht weiter.
                result += " " + text
            }
            previous = line
        }
        return result
    }

    /// `•`, `·`, `▪`, `–` am Zeilenanfang werden zu `- `.
    static func listItem(_ text: String) -> String {
        for bullet in ["•", "·", "▪", "◦", "–", "—"] where text.hasPrefix(bullet) {
            return "- " + text.dropFirst(bullet.count).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    static func isListItem(_ text: String) -> Bool {
        text.hasPrefix("- ") || text.range(of: #"^\d+[.)] "#, options: .regularExpression) != nil
    }
}
