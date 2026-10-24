import Foundation

extension Vault {
    /// Alle `#tags` im ganzen hirni-Ordner, die häufigsten zuerst.
    /// Gezählt wird, in wie vielen Notizen ein Tag vorkommt. Gross/klein gilt
    /// als gleich, angezeigt wird die Schreibweise, die zuerst gefunden wurde.
    public func allTags() -> [(name: String, count: Int)] {
        var counts: [String: (name: String, count: Int)] = [:]
        for url in allNoteURLs() {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for tag in MarkdownSyntax.tags(in: Frontmatter.split(text).body) {
                counts[tag.lowercased(), default: (tag, 0)].count += 1
            }
        }
        return counts.values.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Alle heruntergeladenen Notizen im hirni-Ordner, ohne Systemordner.
    func allNoteURLs() -> [URL] {
        allFiles { Self.isNote(name: $0.lastPathComponent) }
    }

    /// Alle heruntergeladenen Datenbanken im hirni-Ordner, ohne Systemordner.
    func allDatabaseURLs() -> [URL] {
        allFiles(matching: Self.isDatabase)
    }

    private func allFiles(matching include: (URL) -> Bool) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if VaultLayout.isSystemFolder(named: url.lastPathComponent) { enumerator.skipDescendants() }
            } else if include(url) {
                result.append(url)
            }
        }
        // Feste Reihenfolge, damit die angezeigte Schreibweise eines Tags nicht
        // von Start zu Start wechselt.
        return result.sorted { $0.path < $1.path }
    }
}
