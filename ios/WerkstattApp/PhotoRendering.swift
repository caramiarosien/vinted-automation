import Foundation
import ImageIO
import UniformTypeIdentifiers
import WerkstattCore

enum PhotoRendering {
    /// Decode with ImageIO, apply orientation, and write a fresh JPEG without EXIF/GPS.
    static func jpeg(_ data: Data, maximumDimension: Int? = nil) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            throw WerkstattError.validation("Dieses Foto kann nicht gelesen werden. Bitte JPEG, HEIC oder PNG wählen.")
        }
        guard width > 0, height > 0, width <= 30_000, height <= 30_000,
              Int64(width) * Int64(height) <= 150_000_000 else {
            throw WerkstattError.validation("Dieses Bild ist für den Import zu groß.")
        }
        let maxSize = maximumDimension ?? max(width, height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw WerkstattError.validation("Die Bildvorschau konnte nicht erstellt werden.")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw WerkstattError.validation("JPEG-Export konnte nicht gestartet werden.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw WerkstattError.validation("JPEG-Export ist fehlgeschlagen.")
        }
        return output as Data
    }
}
