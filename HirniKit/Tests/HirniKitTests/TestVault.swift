import Foundation
@testable import HirniKit

/// Ein frischer hirni-Ordner im temporären Verzeichnis, pro Test.
final class TestVault {
    let vault: Vault

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "hirni-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try VaultLayout.prepare(root: root)
        vault = Vault(root: root)
    }

    deinit {
        try? FileManager.default.removeItem(at: vault.root)
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: vault.root.appending(path: relativePath).path(percentEncoded: false))
    }

    func write(_ text: String, to relativePath: String) throws {
        let url = vault.root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
