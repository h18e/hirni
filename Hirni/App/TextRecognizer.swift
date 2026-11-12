import CoreGraphics
import HirniKit
import ImageIO
import Vision

/// Erkennt Text auf Fotos (Vision, auf dem Gerät, ohne Internet).
enum TextRecognizer {
    /// Text eines Bildes, zu Absätzen zusammengefügt (`RecognizedText`).
    static func text(in imageData: Data) async throws -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return "" }
        let orientation = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation]
            .flatMap { $0 as? UInt32 }.flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        return try await text(in: image, orientation: orientation)
    }

    static func text(in image: CGImage, orientation: CGImagePropertyOrientation = .up) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "en-US")]
        let observations = try await request.perform(on: image, orientation: orientation)
        let lines = observations.compactMap { observation -> HirniKit.RecognizedText.Line? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return HirniKit.RecognizedText.Line(text: candidate.string, box: observation.boundingBox.cgRect)
        }
        return HirniKit.RecognizedText.compose(lines)
    }

    /// Text mehrerer Bilder (Seiten), getrennt durch eine Leerzeile.
    static func text(in images: [Data]) async throws -> String {
        var pages: [String] = []
        for image in images {
            let text = try await text(in: image)
            if !text.isEmpty { pages.append(text) }
        }
        return pages.joined(separator: "\n\n")
    }
}
