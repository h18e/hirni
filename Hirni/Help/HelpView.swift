import SwiftUI

/// Ein Thema der Hilfe: Abschnitte mit Punkten (Markdown: **fett**, `Code`).
struct HelpTopic: Identifiable, Hashable {
    struct Section: Hashable {
        let title: String
        let items: [String]
    }

    let id: String
    let title: String
    let systemImage: String
    let summary: String
    let sections: [Section]

    /// Kommt `query` irgendwo im Thema vor (Gross/klein egal)?
    func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(separator: " ")
        let text = ([title, summary] + sections.flatMap { [$0.title] + $0.items }).joined(separator: " ").lowercased()
        return words.allSatisfy { text.contains($0) }
    }
}

/// Spalte «Hilfe»: alle Themen, durchsuchbar.
struct HelpListView: View {
    @Environment(VaultStore.self) private var store
    @State private var query = ""

    private var topics: [HelpTopic] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? HelpTopic.all : HelpTopic.all.filter { $0.matches(trimmed) }
    }

    var body: some View {
        @Bindable var store = store
        List(selection: $store.helpTopic) {
            ForEach(topics) { topic in
                VStack(alignment: .leading, spacing: 2) {
                    Label(topic.title, systemImage: topic.systemImage)
                        .font(.headline)
                    Text(topic.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 2)
                .tag(topic.id)
            }
        }
        .navigationTitle("Hilfe")
        .searchable(text: $query, prompt: "In der Hilfe suchen")
        .overlay {
            if topics.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        #endif
    }
}

/// Ein Thema mit allen Abschnitten.
struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label(topic.title, systemImage: topic.systemImage)
                    .font(.largeTitle.bold())
                Text(topic.summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                ForEach(topic.sections, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.title3.bold())
                        ForEach(section.items, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(.tint)
                                Text(Self.markdown(item))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(topic.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
