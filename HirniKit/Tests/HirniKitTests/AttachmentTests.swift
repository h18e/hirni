import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HirniKit

/// Ein kleines PNG in den Grössen `width` × `height`.
private func pngData(width: Int, height: Int) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(red: 1, green: 0.5, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

private func pixelSize(of data: Data) -> (Int, Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (w, h)
}

struct AttachmentLinkTests {
    @Test func parsesEmbedsWithEncodedPaths() {
        let text = "Vorher ![Ferien](_Anhänge/Foto%201.jpg) und ![](<_Anhänge/Plan (alt).pdf>) [kein](link.md)"
        let embeds = AttachmentLinks.embeds(in: text)
        #expect(embeds.map(\.path) == ["_Anhänge/Foto 1.jpg", "_Anhänge/Plan (alt).pdf"])
        #expect(embeds.first?.altText == "Ferien")
    }

    @Test func writesMarkdownThatParsesBack() {
        let markdown = AttachmentLinks.markdown(for: "_Anhänge/Plan (1).pdf")
        #expect(markdown == "![](_Anhänge/Plan%20%281%29.pdf)")
        #expect(AttachmentLinks.embeds(in: markdown).first?.path == "_Anhänge/Plan (1).pdf")
    }

    @Test func kinds() {
        #expect(AttachmentLinks.kind(of: "a/b.JPG") == .image)
        #expect(AttachmentLinks.kind(of: "plan.pdf") == .pdf)
        #expect(AttachmentLinks.kind(of: "notiz.md") == nil)
    }

    @Test func embedsAreGreyAndNotLinks() {
        let spans = MarkdownSyntax.spans(in: "![x](_Anhänge/a.png)")
        #expect(spans.contains { $0.kind == .embed(path: "_Anhänge/a.png") })
        #expect(!spans.contains { if case .link = $0.kind { true } else { false } })
    }
}

struct AttachmentImportTests {
    @Test func importsDataNextToNote() throws {
        let test = try TestVault()
        try test.write("", to: "Privat/Ferien.md")
        let note = test.vault.root.appending(path: "Privat/Ferien.md")

        let first = try test.vault.importAttachment(data: Data([1, 2, 3]), fileExtension: "JPG", baseName: "Foto 23.10.", for: note)
        let second = try test.vault.importAttachment(data: Data([4]), fileExtension: "jpg", baseName: "Foto 23.10.", for: note)
        #expect(first == "![](_Anhänge/Foto-23.10..jpg)")
        #expect(second == "![](_Anhänge/Foto-23.10.-2.jpg)")
        #expect(test.exists("Privat/_Anhänge/Foto-23.10..jpg"))
    }

    @Test func importsFileCopyAndConvertsHEICName() throws {
        let test = try TestVault()
        try test.write("", to: "Inbox/Notiz.md")
        let note = test.vault.inboxURL.appending(path: "Notiz.md")
        let outside = FileManager.default.temporaryDirectory.appending(path: "hirni-plan-\(UUID().uuidString).pdf")
        try Data("%PDF".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        let markdown = try test.vault.importAttachment(copying: outside, for: note)
        let path = try #require(AttachmentLinks.embeds(in: markdown).first?.path)
        #expect(path.hasSuffix(".pdf"))
        #expect(FileManager.default.fileExists(atPath: outside.path(percentEncoded: false))) // Original bleibt
        #expect(test.vault.resolveAttachment(path, for: note).map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } == true)
    }

    @Test func resolveStaysInsideVault() throws {
        let test = try TestVault()
        let note = test.vault.inboxURL.appending(path: "Notiz.md")
        #expect(test.vault.resolveAttachment("../../etc/passwd", for: note) == nil)
        #expect(test.vault.resolveAttachment("https://example.com/a.jpg", for: note) == nil)
        #expect(test.vault.resolveAttachment("/etc/passwd", for: note) == nil)
        #expect(test.vault.resolveAttachment("_Anhänge/a.jpg", for: note) != nil)
    }

    @Test func jpegEncodingShrinksLargeImages() throws {
        let png = try pngData(width: 400, height: 200)
        let jpeg = try #require(ImageEncoding.jpeg(from: png, maxPixelSize: 100))
        let size = try #require(pixelSize(of: jpeg))
        #expect(size.0 == 100 && size.1 == 50)
        // Kleine Bilder werden nicht vergrössert.
        let small = try #require(ImageEncoding.jpeg(from: png))
        #expect(pixelSize(of: small).map { $0.0 } == 400)
    }
}

struct AttachmentMoveTests {
    @Test func movingNoteTakesItsAttachments() throws {
        let test = try TestVault()
        try test.write("Bild: ![](_Anhänge/foto.jpg)", to: "Inbox/Ferien.md")
        try test.write("x", to: "Inbox/_Anhänge/foto.jpg")
        try test.write("", to: "Privat/.keep")

        let moved = try test.vault.move(test.vault.inboxURL.appending(path: "Ferien.md"), to: test.vault.root.appending(path: "Privat"))
        #expect(test.exists("Privat/_Anhänge/foto.jpg"))
        #expect(!test.exists("Inbox/_Anhänge/foto.jpg"))
        #expect(try test.vault.readNote(at: moved) == "Bild: ![](_Anhänge/foto.jpg)")
    }

    @Test func sharedAttachmentIsCopiedAndRenamedOnConflict() throws {
        let test = try TestVault()
        try test.write("![a](_Anhänge/foto.jpg) ![a](_Anhänge/foto.jpg)", to: "Inbox/Ferien.md")
        try test.write("![](_Anhänge/foto.jpg)", to: "Inbox/Andere.md")
        try test.write("neu", to: "Inbox/_Anhänge/foto.jpg")
        try test.write("alt", to: "Privat/_Anhänge/foto.jpg") // am Ziel schon belegt

        let moved = try test.vault.move(test.vault.inboxURL.appending(path: "Ferien.md"), to: test.vault.root.appending(path: "Privat"))
        #expect(test.exists("Inbox/_Anhänge/foto.jpg"))                // noch von «Andere» gebraucht
        #expect(try String(contentsOf: test.vault.root.appending(path: "Privat/_Anhänge/foto-2.jpg"), encoding: .utf8) == "neu")
        #expect(try test.vault.readNote(at: moved) == "![a](_Anhänge/foto-2.jpg) ![a](_Anhänge/foto-2.jpg)")
    }
}
