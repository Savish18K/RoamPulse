import Foundation
import ImageIO
import UniformTypeIdentifiers

// Full size JPEG (max 2048 px) and a thumbnail
struct PreparedImage: Equatable {
    var data: Data
    var thumbnail: Data
    var pixelWidth: Int
    var pixelHeight: Int
}

// Shrinks photos before saving, also strips metadata like GPS
enum ImageProcessor {
    static let maxPixelSize = 2048
    static let thumbnailPixelSize = 400
    static let jpegQuality = 0.8

    // nil if it's not an image. Slow for big photos so call it off the main thread
    static func prepare(_ data: Data) -> PreparedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let full = downsample(source, maxPixelSize: maxPixelSize),
              let small = downsample(source, maxPixelSize: thumbnailPixelSize),
              let fullData = jpeg(full),
              let smallData = jpeg(small) else { return nil }
        return PreparedImage(data: fullData, thumbnail: smallData, pixelWidth: full.width, pixelHeight: full.height)
    }

    // Doesn't upscale small images
    private static func downsample(_ source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Fix the EXIF orientation
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
