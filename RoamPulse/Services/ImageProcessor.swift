import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo made ready for saving: a full-size JPEG no bigger than 2048 px on its long side,
/// and a small thumbnail for lists and cards.
struct PreparedImage: Equatable {
    var data: Data
    var thumbnail: Data
    var pixelWidth: Int
    var pixelHeight: Int
}

/// Shrinks photos picked from the library before they are saved in Core Data.
///
/// An iPhone photo is 12–48 megapixels (3–10 MB as HEIC, ~190 MB once decoded). Nothing in the
/// app is shown larger than a full-screen header, so keeping the original would waste storage and
/// memory. ImageIO makes the smaller versions straight from the file without ever decoding the full
/// image, and writing a new JPEG also drops the photo's metadata (such as its GPS location).
enum ImageProcessor {
    static let maxPixelSize = 2048
    static let thumbnailPixelSize = 400
    static let jpegQuality = 0.8

    /// Returns nil if `data` isn't an image. Works with HEIC, JPEG and PNG.
    /// Slow for big photos (tens of milliseconds), so call it off the main thread.
    static func prepare(_ data: Data) -> PreparedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let full = downsample(source, maxPixelSize: maxPixelSize),
              let small = downsample(source, maxPixelSize: thumbnailPixelSize),
              let fullData = jpeg(full),
              let smallData = jpeg(small) else { return nil }
        return PreparedImage(data: fullData, thumbnail: smallData, pixelWidth: full.width, pixelHeight: full.height)
    }

    /// The image scaled so its longest side is at most `maxPixelSize`. Smaller images are not enlarged.
    private static func downsample(_ source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Applies the EXIF orientation, so portrait photos aren't saved sideways.
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
