import AppIntents
import HirniKit
import SwiftUI
import WidgetKit

@main
struct HirniWidgets: WidgetBundle {
    var body: some Widget {
        PendenzenWidget()
    }
}

/// Offene Pendenzen aus Hirni, fällige zuerst. Die Daten legt die App im
/// gemeinsamen App-Gruppen-Ordner ab (`WidgetSnapshot`).
struct PendenzenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Pendenzen", provider: SnapshotProvider()) { entry in
            PendenzenView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Pendenzen")
        .description("Offene Pendenzen aus Hirni, fällige zuerst.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        #endif
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var display = WidgetDisplay()
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetSnapshot(openCount: 3, items: [
            .init(id: "1", text: "Steuererklärung #büro", note: "Büro", notePath: "", due: nil),
            .init(id: "2", text: "Velo flicken", note: "Haus", notePath: "", due: nil),
            .init(id: "3", text: "Geschenk für Lea", note: "Kinder", notePath: "", due: nil),
        ]))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // Die App meldet Änderungen; um Mitternacht neu, damit «heute» und
        // «überfällig» stimmen.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [entry()], policy: .after(midnight)))
    }

    private func entry() -> SnapshotEntry {
        let folder = AppGroup.folder
        return SnapshotEntry(
            date: .now,
            snapshot: folder.flatMap(WidgetSnapshot.load) ?? WidgetSnapshot(),
            display: folder.map(WidgetDisplay.load) ?? WidgetDisplay()
        )
    }
}

struct PendenzenView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    /// Sperrbildschirm (nur iPhone).
    private var isAccessory: Bool {
        #if os(iOS)
        family == .accessoryRectangular
        #else
        false
        #endif
    }

    /// Platz in Zeilen einer Pendenz; eine Kategorie-Überschrift braucht etwa
    /// die Hälfte.
    private var budget: Double {
        #if os(macOS)
        // Mac-Widgets sind etwas niedriger.
        switch family {
        case .systemSmall: 4.5
        case .systemMedium: 3.1
        default: 8
        }
        #else
        switch family {
        case .systemSmall: 4.5
        case .systemMedium: 3.6
        default: 9
        }
        #endif
    }

    private var pages: [[WidgetLine]] {
        WidgetLayout.pages(entry.snapshot, display: entry.display, budget: budget)
    }

    var body: some View {
        if isAccessory {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.snapshot.openCount) Pendenzen").font(.headline)
                ForEach(entry.snapshot.items.prefix(2)) { item in
                    Text(item.text).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DeepLink.tasks)
        } else {
            let pages = pages
            let current = min(entry.display.page, max(0, pages.count - 1))
            VStack(alignment: .leading, spacing: family == .systemSmall ? 3 : 4) {
                HStack {
                    Label("Pendenzen", systemImage: "checklist")
                        .labelStyle(family == .systemSmall ? AnyLabelStyle(.titleOnly) : AnyLabelStyle(.titleAndIcon))
                        .font(.headline)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                    Spacer()
                    if pages.count > 1 {
                        pager(current: current, count: pages.count)
                    } else {
                        Text("\(entry.snapshot.openCount)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if entry.snapshot.items.isEmpty {
                    Spacer()
                    Text("Alles erledigt 🎉")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ForEach(pages.indices.contains(current) ? pages[current] : []) { line in
                        switch line {
                        case .header(let category, let count, let collapsed):
                            categoryHeader(category, count: count, collapsed: collapsed)
                        case .item(let item):
                            row(item)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .widgetURL(DeepLink.tasks)
        }
    }

    /// Kategorie: ein Tipp klappt sie auf oder zu.
    private func categoryHeader(_ category: String?, count: Int, collapsed: Bool) -> some View {
        Button(intent: ToggleCategoryIntent(category: category)) {
            HStack(spacing: 4) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 10)
                Text(category.map { "#" + $0 } ?? "Ohne Kategorie")
                    .lineLimit(1)
                if collapsed {
                    Text("\(count)").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    /// Blättern: WidgetKit kennt kein Scrollen.
    private func pager(current: Int, count: Int) -> some View {
        HStack(spacing: 8) {
            if family != .systemSmall {
                Text("\(current + 1)/\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            pageButton("chevron.up", to: current - 1, enabled: current > 0)
            pageButton("chevron.down", to: current + 1, enabled: current + 1 < count)
        }
    }

    private func pageButton(_ symbol: String, to page: Int, enabled: Bool) -> some View {
        Button(intent: WidgetPageIntent(page: page)) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    private func row(_ item: WidgetSnapshot.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Der Kreis hakt ab, der Text öffnet die Notiz.
            Button(intent: CompleteTaskIntent(id: item.id)) {
                Image(systemName: "circle")
                    .font(family == .systemSmall ? .caption : .body)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Link(destination: DeepLink.note(item.notePath)) {
                text(item)
            }
        }
    }

    private func text(_ item: WidgetSnapshot.Item) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.withoutCategory(item))
                    .font(family == .systemSmall ? .caption : .subheadline)
                    .lineLimit(1)
                if family != .systemSmall {
                    Text(subtitle(item))
                        .font(.caption2)
                        .foregroundStyle(isOverdue(item) ? .red : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Die Kategorie steht schon in der Überschrift.
    static func withoutCategory(_ item: WidgetSnapshot.Item) -> String {
        guard let category = item.category,
              let range = item.text.range(of: "#" + category, options: .caseInsensitive)
        else { return item.text }
        var text = item.text
        text.removeSubrange(range)
        let trimmed = text.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? item.text : trimmed
    }

    private func subtitle(_ item: WidgetSnapshot.Item) -> String {
        guard let due = item.dueDate else { return item.note }
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(due) { day = "heute" }
        else if calendar.isDateInTomorrow(due) { day = "morgen" }
        else { day = due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
        return "\(item.note) · fällig \(day)"
    }

    private func isOverdue(_ item: WidgetSnapshot.Item) -> Bool {
        guard let due = item.dueDate else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }
}

/// Damit die Kopfzeile je nach Grösse mit oder ohne Symbol erscheint.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init(_ style: some LabelStyle) {
        make = { AnyView(Label($0).labelStyle(style)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

/// Links vom Widget in die App: `hirni://pendenzen`, `hirni://notiz?pfad=…`.
enum DeepLink {
    static let tasks = URL(string: "hirni://pendenzen")!

    static func note(_ path: String) -> URL {
        var parts = URLComponents()
        parts.scheme = "hirni"
        parts.host = "notiz"
        parts.queryItems = [URLQueryItem(name: "pfad", value: path)]
        return parts.url ?? tasks
    }
}
