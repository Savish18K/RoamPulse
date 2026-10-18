import SwiftUI
import UIKit

/// A trip's cover: the photo the user picked (saved in Core Data), or else the sample photo
/// for the destination. Fills the space it is given, like `PhotoView`.
struct TripCoverView: View {
    @Environment(TripStore.self) private var store
    let trip: Trip
    /// Lists use the 400 px thumbnail; big headers use the full 2048 px photo.
    var thumbnail = false
    var showsSymbol = true

    @State private var loadedImage: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image = customImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    PhotoView(photo: trip.cover, showsSymbol: showsSymbol)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: trip.coverImageID) {
                loadedImage = await loadCustomImage()
            }
    }

    /// Taken from the cache when possible, so a photo seen before appears straight away.
    private var customImage: UIImage? {
        guard let id = trip.coverImageID else { return nil }
        return ImageCache.shared.object(forKey: ImageCache.key(id, thumbnail: thumbnail)) ?? loadedImage
    }

    private func loadCustomImage() async -> UIImage? {
        guard let id = trip.coverImageID else { return nil }
        let key = ImageCache.key(id, thumbnail: thumbnail)
        if let cached = ImageCache.shared.object(forKey: key) {
            return cached
        }
        // Reading from Core Data happens on the main thread (its context belongs to it), but
        // decoding the JPEG is the slow part, so that runs in the background.
        guard let data = store.imageData(id, thumbnail: thumbnail) else { return nil }
        let image = await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
        if let image {
            ImageCache.shared.setObject(image, forKey: key)
        }
        return image
    }
}

/// Decoded photos kept in memory, so scrolling back to a trip doesn't decode its photo again.
/// NSCache empties itself when the iPhone is low on memory.
enum ImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40
        return cache
    }()

    static func key(_ id: UUID, thumbnail: Bool) -> NSString {
        "\(id.uuidString)-\(thumbnail ? "thumb" : "full")" as NSString
    }
}
