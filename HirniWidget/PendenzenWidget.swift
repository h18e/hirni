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
}

struct SnapshotProvider: TimelineProvider {
    static let appGroup = "group.ch.hebera.hirni"

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
        let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)
        return SnapshotEntry(date: .now, snapshot: folder.flatMap(WidgetSnapshot.load) ?? WidgetSnapshot())
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

    private var maxItems: Int {
        if isAccessory { return 2 }
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 3
        default: return 8
        }
    }

    var body: some View {
        if isAccessory {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.snapshot.openCount) Pendenzen").font(.headline)
                ForEach(entry.snapshot.items.prefix(maxItems)) { item in
                    Text(item.text).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DeepLink.tasks)
        } else {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 6) {
                HStack {
                    Label("Pendenzen", systemImage: "checklist")
                        .labelStyle(family == .systemSmall ? AnyLabelStyle(.titleOnly) : AnyLabelStyle(.titleAndIcon))
                        .font(.headline)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                    Spacer()
                    Text("\(entry.snapshot.openCount)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if entry.snapshot.items.isEmpty {
                    Spacer()
                    Text("Alles erledigt 🎉")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ForEach(entry.snapshot.items.prefix(maxItems)) { item in
                        Link(destination: DeepLink.note(item.notePath)) {
                            row(item)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .widgetURL(DeepLink.tasks)
        }
    }

    private func row(_ item: WidgetSnapshot.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.text)
                    .font(family == .systemSmall ? .caption : .subheadline)
                    .lineLimit(1)
                if family != .systemSmall {
                    Text(subtitle(item))
                        .font(.caption2)
                        .foregroundStyle(isOverdue(item) ? .red : .secondary)
                        .lineLimit(1)
                }
            }
        }
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
