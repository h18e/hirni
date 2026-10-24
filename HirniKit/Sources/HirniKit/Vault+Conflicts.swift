import Foundation

/// Eine andere Fassung einer Notiz, die iCloud nicht von selbst
/// zusammenführen konnte (z. B. beide Geräte haben offline dieselbe Notiz
/// geändert).
public struct ConflictVersion: Identifiable, Hashable, Sendable {
    public let id: String
    public let modified: Date?
    /// Gerät, das diese Fassung gespeichert hat, z. B. «iPhone von Raphael».
    public let deviceName: String?
    public let text: String
}

public enum ConflictChoice: Sendable {
    /// Die Fassung auf diesem Gerät behalten, die anderen verwerfen.
    case keepCurrent
    /// Eine andere Fassung übernehmen.
    case takeOther(ConflictVersion)
    /// Alles behalten: Die anderen Fassungen werden zu eigenen Notizen.
    case keepAll
}

extension Vault {
    public func conflictVersions(of url: URL) -> [ConflictVersion] {
        (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).compactMap { version in
            guard let text = try? String(contentsOf: version.url, encoding: .utf8) else { return nil }
            return ConflictVersion(
                id: Self.identifier(of: version),
                modified: version.modificationDate,
                deviceName: version.localizedNameOfSavingComputer,
                text: text
            )
        }
    }

    /// Löst den Konflikt auf. Liefert bei `keepAll` die neu angelegten Notizen.
    @discardableResult
    public func resolveConflict(at url: URL, choice: ConflictChoice) throws -> [URL] {
        let others = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        var created: [URL] = []

        switch choice {
        case .keepCurrent:
            break
        case .takeOther(let chosen):
            guard let version = others.first(where: { Self.identifier(of: $0) == chosen.id }) else { break }
            try Coordinated.write(url, options: .forReplacing) { url in
                _ = try version.replaceItem(at: url, options: [])
            }
        case .keepAll:
            for version in others {
                guard let text = try? String(contentsOf: version.url, encoding: .utf8) else { continue }
                created.append(try saveConflictCopy(text: text, of: url, deviceName: version.localizedNameOfSavingComputer))
            }
        }

        for version in others { version.isResolved = true }
        try Coordinated.write(url) { url in
            try NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
        return created
    }

    /// Legt `text` als eigene Notiz neben `note` ab, z. B. «Einkauf (iPhone)».
    /// Gebraucht bei Konflikten, wenn beide Fassungen behalten werden sollen.
    public func saveConflictCopy(text: String, of note: URL, deviceName: String?) throws -> URL {
        let suffix = deviceName.map { "(\($0))" } ?? "(Konflikt)"
        let copy = try createNote(
            in: note.deletingLastPathComponent(),
            title: "\(Self.title(of: note)) \(suffix)",
            // Eine Kopie ist nicht angepinnt, sonst gäbe es zwei angepinnte Notizen.
            text: Frontmatter.setting(Frontmatter.pinnedKey, to: nil, in: text)
        )
        return copy
    }

    private static func identifier(of version: NSFileVersion) -> String {
        if let date = version.modificationDate {
            return "\(date.timeIntervalSinceReferenceDate)-\(version.localizedNameOfSavingComputer ?? "")"
        }
        return version.url.lastPathComponent
    }
}
