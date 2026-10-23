import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Fotos für Anhänge vorbereiten.
public enum ImageEncoding {
    /// Längste Seite in Pixeln. Reicht für Bildschirm und Druck und hält iCloud schlank.
    public static let maxPixelSize = 3000

    /// Wandelt ein Bild (HEIC, PNG, JPEG …) in JPEG um und verkleinert es bei
    /// Bedarf. JPEG statt HEIC, damit auch Obsidian und Browser es anzeigen.
    /// Die Drehung aus der Kamera wird dabei fest ins Bild übernommen.
    public static func jpeg(from data: Data, maxPixelSize: Int = maxPixelSize, quality: Double = 0.85) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
