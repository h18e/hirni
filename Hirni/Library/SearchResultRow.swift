import HirniKit
import SwiftUI

/// Ein Suchtreffer: Titel, Ordner und Textausschnitt mit hervorgehobenen Wörtern.
struct SearchResultRow: View {
    let hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hit.title)
                .font(.headline)
                .lineLimit(1)
            Label(hit.folder.isEmpty ? "hirni" : hit.folder, systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !hit.snippet.isEmpty {
                Text(Self.highlighted(hit.snippet))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    /// Wandelt die Markierungen des Index in fett gedruckte Stellen um.
    static func highlighted(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        var isMatch = false
        var current = ""
        func flush() {
            guard !current.isEmpty else { return }
            var part = AttributedString(current)
            if isMatch {
                part.font = .subheadline.bold()
                part.foregroundColor = .primary
            }
            result += part
            current = ""
        }
        for character in snippet {
            switch character {
            case SearchHit.highlightStart: flush(); isMatch = true
            case SearchHit.highlightEnd: flush(); isMatch = false
            case "\n": current.append(" ")
            default: current.append(character)
            }
        }
        flush()
        return result
    }
}
