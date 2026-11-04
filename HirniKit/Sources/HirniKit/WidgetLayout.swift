import Foundation

/// Was im Widget eingestellt ist: zugeklappte Kategorien und die Seite. Liegt
/// im gemeinsamen App-Gruppen-Ordner, gilt also pro Gerät.
public struct WidgetDisplay: Codable, Equatable, Sendable {
    public static let fileName = "WidgetAnzeige.json"

    /// Zugeklappt, klein geschrieben; `""` = «Ohne Kategorie».
    public var collapsed: Set<String> = []
    public var page = 0

    public init() {}

    public static func key(_ category: String?) -> String {
        category?.lowercased() ?? ""
    }

    public mutating func toggle(_ category: String?) {
        let key = Self.key(category)
        if collapsed.remove(key) == nil { collapsed.insert(key) }
    }

    public static func load(from folder: URL) -> WidgetDisplay {
        guard let data = try? Data(contentsOf: folder.appending(path: fileName)),
              let display = try? JSONDecoder().decode(WidgetDisplay.self, from: data)
        else { return WidgetDisplay() }
        return display
    }

    public func save(to folder: URL) throws {
        try JSONEncoder().encode(self).write(to: folder.appending(path: Self.fileName), options: .atomic)
    }
}

/// Eine Zeile im Widget: Kategorie-Überschrift oder Pendenz.
public enum WidgetLine: Identifiable, Equatable, Sendable {
    case header(category: String?, count: Int, collapsed: Bool)
    case item(WidgetSnapshot.Item)

    public var id: String {
        switch self {
        case .header(let category, _, _): "#" + WidgetDisplay.key(category)
        case .item(let item): item.id
        }
    }

    /// Platz in Zeilen einer Pendenz. Überschriften brauchen etwa die Hälfte.
    var height: Double {
        if case .header = self { 0.55 } else { 1 }
    }
}

/// Verteilt die Pendenzen auf Seiten. WidgetKit kennt kein Scrollen; darum
/// blättert man mit Knöpfen. Ein Widget zeigt immer genau eine Seite.
public enum WidgetLayout {
    /// `budget`: Platz pro Seite, in Zeilen einer Pendenz. Läuft eine Kategorie
    /// über die Seite hinaus, steht ihre Überschrift oben wieder.
    public static func pages(_ snapshot: WidgetSnapshot, display: WidgetDisplay, budget: Double) -> [[WidgetLine]] {
        var pages: [[WidgetLine]] = []
        var page: [WidgetLine] = []
        var used = 0.0

        func add(_ line: WidgetLine) {
            if !page.isEmpty, used + line.height > budget {
                pages.append(page)
                page = []
                used = 0
            }
            page.append(line)
            used += line.height
        }

        var start = snapshot.items.startIndex
        while start < snapshot.items.endIndex {
            let key = WidgetDisplay.key(snapshot.items[start].category)
            let end = snapshot.items[start...].firstIndex { WidgetDisplay.key($0.category) != key } ?? snapshot.items.endIndex
            let items = snapshot.items[start..<end]
            let collapsed = display.collapsed.contains(key)
            let header = WidgetLine.header(category: items.first?.category, count: items.count, collapsed: collapsed)
            // Die Überschrift nicht allein unten auf der Seite lassen.
            let needed = header.height + (collapsed ? 0 : 1)
            if !page.isEmpty, used + needed > budget {
                pages.append(page)
                page = []
                used = 0
            }
            add(header)
            if !collapsed {
                for item in items {
                    if !page.isEmpty, used + 1 > budget {
                        pages.append(page)
                        page = [header]
                        used = header.height
                    }
                    add(.item(item))
                }
            }
            start = end
        }
        if !page.isEmpty { pages.append(page) }
        return pages
    }
}
