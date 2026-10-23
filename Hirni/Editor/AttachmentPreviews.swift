import Foundation
import HirniKit
import ImageIO
import PDFKit

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

/// Lädt und merkt sich verkleinerte Vorschauen von Bildern und PDFs.
/// Geladen wird im Hintergrund; danach ruft `load` die Rückmeldung auf.
@MainActor
final class AttachmentPreviews {
    static let shared = AttachmentPreviews()

    enum Preview {
        case image(PlatformImage, aspectRatio: CGFloat)
        case missing
    }

    private var cache: [URL: Preview] = [:]
    private var loading: Set<URL> = []
    private var waiting: [URL: [() -> Void]] = [:]

    /// Grösste Seite der Vorschau in Pixeln. Genug für den Bildschirm, spart Speicher.
    private nonisolated static let maxPixelSize = 1600

    func preview(for url: URL) -> Preview? {
        cache[url]
    }

    func load(_ url: URL, then completion: @escaping () -> Void) {
        if cache[url] != nil { return completion() }
        waiting[url, default: []].append(completion)
        guard loading.insert(url).inserted else { return }

        Task.detached(priority: .userInitiated) {
            let image = Self.render(url)
            await MainActor.run {
                self.cache[url] = image.map { .image(PlatformImage(cgImage: $0), aspectRatio: CGFloat($0.width) / CGFloat(max($0.height, 1))) } ?? .missing
                self.loading.remove(url)
                self.waiting.removeValue(forKey: url)?.forEach { $0() }
            }
        }
    }

    /// Nach einer Änderung an der Datei neu laden.
    func forget(_ url: URL) {
        cache.removeValue(forKey: url)
    }

    // MARK: - Hintergrund

    private nonisolated static func render(_ url: URL) -> CGImage? {
        // Koordiniertes Lesen lädt eine iCloud-Datei bei Bedarf zuerst herunter.
        var result: CGImage?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: nil) { url in
            switch AttachmentLinks.kind(of: url.lastPathComponent) {
            case .image: result = thumbnail(ofImageAt: url)
            case .pdf: result = thumbnail(ofPDFAt: url)
            case nil: result = nil
            }
        }
        return result
    }

    private nonisolated static func thumbnail(ofImageAt url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Erste Seite des PDFs.
    private nonisolated static func thumbnail(ofPDFAt url: URL) -> CGImage? {
        guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = CGFloat(maxPixelSize) / max(bounds.width, bounds.height)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        #if os(iOS)
        return image.cgImage
        #else
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}

#if os(macOS)
extension NSImage {
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
#endif
