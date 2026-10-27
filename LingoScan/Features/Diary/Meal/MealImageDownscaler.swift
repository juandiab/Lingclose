import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reduce una foto a JPEG de, como mucho, 1024 px de lado mayor, calidad 0,8 y sin metadatos (ni EXIF ni
/// ubicación): es lo único que sale del teléfono. La orientación se aplica a los píxeles.
enum MealImageDownscaler {
    static let maxSide = 1024
    static let quality = 0.8

    /// `nil` si los datos no son una imagen legible. Nunca amplía una imagen pequeña.
    @concurrent
    static func jpeg(from data: Data) async -> Data? {
        reduced(data)
    }

    static func reduced(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let side = min(max(width, height), maxSide)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        // Solo la calidad: sin diccionario de metadatos, el JPEG sale sin EXIF.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
