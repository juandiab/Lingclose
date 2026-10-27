import Foundation
import ImageIO
import Testing
import UIKit
@testable import LingoScan

struct MealImageDownscalerTests {
    private func jpeg(width: Int, height: Int) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }())
        return renderer.jpegData(withCompressionQuality: 1) { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func size(of data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        return (p[kCGImagePropertyPixelWidth] as? Int ?? 0, p[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    @Test func largeImageIsReducedToAThousandTwentyFourOnTheLongSide() throws {
        let out = try #require(MealImageDownscaler.reduced(jpeg(width: 3000, height: 1500)))
        let (w, h) = try #require(size(of: out))
        #expect(max(w, h) == 1024 && min(w, h) == 512)
        #expect(out.prefix(2) == Data([0xFF, 0xD8]), "es un JPEG")
    }

    @Test func smallImageIsNotUpscaled() throws {
        let out = try #require(MealImageDownscaler.reduced(jpeg(width: 300, height: 200)))
        let (w, h) = try #require(size(of: out))
        #expect(w == 300 && h == 200)
    }

    /// JPEG con metadatos sensibles (cámara, fecha, ubicación) como los que trae una foto real.
    private func jpegWithMetadata() throws -> Data {
        let plain = try #require(UIImage(data: jpeg(width: 800, height: 600))?.cgImage)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "CamaraSecreta"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:27 12:00:00"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 4.6, kCGImagePropertyGPSLatitudeRef: "N"],
        ]
        CGImageDestinationAddImage(destination, plain, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func outputDropsCameraDateAndLocationMetadata() throws {
        let input = try jpegWithMetadata()
        let inSource = try #require(CGImageSourceCreateWithData(input as CFData, nil))
        let inProps = try #require(CGImageSourceCopyPropertiesAtIndex(inSource, 0, nil) as? [CFString: Any])
        #expect(inProps[kCGImagePropertyGPSDictionary] != nil, "la entrada sí traía ubicación")
        let out = try #require(MealImageDownscaler.reduced(input))
        let source = try #require(CGImageSourceCreateWithData(out as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect(tiff?[kCGImagePropertyTIFFMake] == nil)
    }

    @Test func nonImageDataReturnsNil() {
        #expect(MealImageDownscaler.reduced(Data("no soy una imagen".utf8)) == nil)
    }
}
