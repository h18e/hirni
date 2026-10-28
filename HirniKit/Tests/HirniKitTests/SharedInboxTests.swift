import Foundation
import Testing
@testable import HirniKit

struct SharedInboxTests {
    @Test func titleSuggestion() {
        #expect(SharedItem.suggestedTitle(text: "Rezept Zopf\nMehl", url: nil) == "Rezept Zopf")
        #expect(SharedItem.suggestedTitle(text: "https://www.sbb.ch/x", url: URL(string: "https://www.sbb.ch/x")) == "sbb.ch")
        #expect(SharedItem.suggestedTitle(text: "", url: nil) == "Geteilt")
        #expect(SharedItem.suggestedTitle(text: String(repeating: "a", count: 80), url: nil).count == 61)
    }

    @Test func importsTextAndAttachments() throws {
        let test = try TestVault()
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let image = tmp.appending(path: "Foto 1.png")
        try Data([1, 2, 3]).write(to: image)

        let note = try test.vault.importShared(SharedItem(title: "Velo", text: "https://velo.ch"), files: [image])
        #expect(note.lastPathComponent == "Velo.md")
        #expect(try test.vault.readNote(at: note) == "https://velo.ch\n\n![](_Anhänge/Foto-1.png)\n")
        #expect(test.exists("Inbox/_Anhänge/Foto-1.png"))
    }

    @Test func queueRoundTrip() throws {
        let test = try TestVault()
        let queue = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let file = FileManager.default.temporaryDirectory.appending(path: "beleg.pdf")
        try Data([9]).write(to: file)
        try SharedInbox.enqueue(SharedItem(title: "Beleg", text: "Quittung"), files: [file], in: queue)
        try SharedInbox.enqueue(SharedItem(title: "", text: "Nur Text"), files: [], in: queue)

        let notes = SharedInbox.importPending(from: queue, into: test.vault)
        #expect(Set(notes.map(\.lastPathComponent)) == ["Beleg.md", "Geteilt.md"])
        #expect(test.exists("Inbox/_Anhänge/beleg.pdf"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: queue.path(percentEncoded: false)).isEmpty)
    }
}
