import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Speicherschonendes Laden und Kodieren von Bildern über ImageIO.
enum ImageCodec {
    private static func thumbOptions(_ maxPixel: Int) -> CFDictionary {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
    }

    /// Dekodiert direkt in verkleinerter Größe – das Originalbild wird nie voll in den Speicher geladen.
    static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions(maxPixel))
    }

    static func downsample(fileURL: URL, maxPixel: Int) -> CGImage? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(fileURL as CFURL, opts) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions(maxPixel))
    }

    /// HEIC (sehr kompakt), mit JPEG als Rückfall. Liefert Daten und Dateiendung.
    static func encodeCompact(_ image: CGImage, quality: Double) -> (data: Data, ext: String)? {
        if let d = encode(image, type: UTType.heic, quality: quality) { return (d, "heic") }
        if let d = encode(image, type: UTType.jpeg, quality: quality) { return (d, "jpg") }
        return nil
    }

    static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        encode(image, type: .jpeg, quality: quality)
    }

    static func encodePNG(_ image: CGImage) -> Data? {
        encode(image, type: .png, quality: 1)
    }

    private static func encode(_ image: CGImage, type: UTType, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        let props = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(dest, image, props)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
