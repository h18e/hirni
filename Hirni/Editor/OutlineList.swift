import HirniKit
import SwiftUI

/// Inhaltsverzeichnis einer Notiz: Überschriften eingerückt nach Ebene.
struct OutlineList: View {
    let headings: [MarkdownSyntax.Heading]
    let select: (MarkdownSyntax.Heading) -> Void

    var body: some View {
        let topLevel = headings.map(\.level).min() ?? 1
        Group {
            if headings.isEmpty {
                ContentUnavailableView(
                    "Keine Überschriften",
                    systemImage: "list.bullet.indent",
                    description: Text("Zeilen mit # am Anfang erscheinen hier.")
                )
            } else {
                List(headings) { heading in
                    Button {
                        select(heading)
                    } label: {
                        Text(heading.title)
                            .font(heading.level == topLevel ? .body.weight(.semibold) : .body)
                            .foregroundStyle(heading.level > topLevel + 1 ? .secondary : .primary)
                            .lineLimit(2)
                            .padding(.leading, CGFloat(heading.level - topLevel) * 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Inhaltsverzeichnis")
        #if os(macOS)
        .frame(width: 300, height: 360)
        #endif
    }
}
