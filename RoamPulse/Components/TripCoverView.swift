import SwiftUI
import UIKit

/// A photo the user picked, loaded from Core Data (`StoredImageEntity`). While it loads, or if it is
/// missing, `placeholder` is shown. Fills the space it is given, like `PhotoView`.
struct StoredImageView<Placeholder: View>: View {
    @Environment(TripStore.self) private var store
    let imageID: UUID?
    /// Lists use the 400 px thumbnail; big headers use the full 2048 px photo.
    var thumbnail = false
    @ViewBuilder var placeholder: Placeholder

    @State private var loadedImage: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image = displayedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipped()
            .task(id: imageID) {
                loadedImage = await load()
            }
    }

    /// Taken from the cache when possible, so a photo seen before appears straight away.
    private var displayedImage: UIImage? {
        guard let imageID else { return nil }
        return ImageCache.shared.object(forKey: ImageCache.key(imageID, thumbnail: thumbnail)) ?? loadedImage
    }

    private func load() async -> UIImage? {
        guard let imageID else { return nil }
        let key = ImageCache.key(imageID, thumbnail: thumbnail)
        if let cached = ImageCache.shared.object(forKey: key) {
            return cached
        }
        // Reading from Core Data happens on the main thread (its context belongs to it), but
        // decoding the JPEG is the slow part, so that runs in the background.
        guard let data = store.imageData(imageID, thumbnail: thumbnail) else { return nil }
        let image = await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
        if let image {
            ImageCache.shared.setObject(image, forKey: key)
        }
        return image
    }
}

/// A trip's cover: the photo the user picked (saved in Core Data), or else the sample photo
/// for the destination.
struct TripCoverView: View {
    let trip: Trip
    var thumbnail = false
    var showsSymbol = true

    var body: some View {
        StoredImageView(imageID: trip.coverImageID, thumbnail: thumbnail) {
            PhotoView(photo: trip.cover, showsSymbol: showsSymbol)
        }
        .accessibilityHidden(true)
    }
}

/// One photo of a journal memory: a sample photo, or one the user picked.
struct MemoryPhotoView: View {
    let photo: MemoryPhoto
    var thumbnail = false

    var body: some View {
        switch photo {
        case .sample(let sample):
            PhotoView(photo: sample)
        case .stored(let imageID):
            StoredImageView(imageID: imageID, thumbnail: thumbnail) {
                Rectangle().fill(Theme.fill)
                    .overlay { ProgressView() }
            }
            .accessibilityHidden(true)
        }
    }
}

/// Decoded photos kept in memory, so scrolling back to a photo doesn't decode it again.
/// NSCache empties itself when the iPhone is low on memory.
enum ImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        return cache
    }()

    static func key(_ id: UUID, thumbnail: Bool) -> NSString {
        "\(id.uuidString)-\(thumbnail ? "thumb" : "full")" as NSString
    }
}
