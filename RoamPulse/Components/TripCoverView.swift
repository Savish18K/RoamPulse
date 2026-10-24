import SwiftUI
import UIKit

// Image saved in Core Data, shows the placeholder while loading
struct StoredImageView<Placeholder: View>: View {
    @Environment(TripStore.self) private var store
    let imageID: UUID?
    // Thumbnail for lists, full size for headers
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
        // Read on the main thread (context), decode in the background
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

// User's cover photo, or the sample photo for the destination
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

// NSCache clears itself when memory is low
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
