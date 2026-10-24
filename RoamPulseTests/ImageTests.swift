import CoreData
import Foundation
import Testing
import UIKit
@testable import RoamPulse

/// Resizing picked photos, saving them in Core Data as trip covers, and the Create Trip form's photo.
@MainActor
struct ImageTests {
    let now = Calendar.trip.date(2026, 12, 13, 16, 40)
    let persistence = PersistenceController(inMemory: true)

    /// A plain JPEG of the given size, standing in for a photo from the library.
    private func photo(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func pixelSize(of data: Data) -> CGSize? {
        UIImage(data: data).map { CGSize(width: $0.size.width * $0.scale, height: $0.size.height * $0.scale) }
    }

    private func trip() -> Trip {
        Trip(name: "Southern Coast", destination: "Galle", startDate: now, endDate: now, budget: 90_000,
             members: [Member(name: "Savishka", colorHex: 0, isMe: true)], cover: .galleFort)
    }

    /// A store backed by a real (in-memory) Core Data database.
    private func coreDataStore() -> (TripStore, CoreDataTripRepository) {
        let repository = CoreDataTripRepository(context: persistence.container.viewContext)
        return (TripStore(repository: repository, clock: FixedClock(now: now)), repository)
    }

    private func imageCount() throws -> Int {
        try persistence.container.viewContext.count(for: StoredImageEntity.fetchRequest())
    }

    @Test func aBigPhotoIsShrunkTo2048PixelsWithASmallThumbnail() throws {
        let prepared = try #require(ImageProcessor.prepare(photo(width: 4032, height: 3024)))
        #expect(max(prepared.pixelWidth, prepared.pixelHeight) == ImageProcessor.maxPixelSize)
        #expect(prepared.pixelWidth > prepared.pixelHeight, "landscape stays landscape")

        let thumbnail = try #require(pixelSize(of: prepared.thumbnail))
        #expect(max(thumbnail.width, thumbnail.height) == CGFloat(ImageProcessor.thumbnailPixelSize))
        #expect(prepared.thumbnail.count < prepared.data.count)
    }

    @Test func aSmallPhotoIsNotEnlarged() throws {
        let prepared = try #require(ImageProcessor.prepare(photo(width: 300, height: 200)))
        #expect(prepared.pixelWidth == 300)
        #expect(prepared.pixelHeight == 200)
    }

    @Test func dataThatIsNotAPhotoIsRejected() {
        #expect(ImageProcessor.prepare(Data("not a photo".utf8)) == nil)
    }

    @Test func aCoverPhotoIsSavedAndLoadsBackWithTheTrip() throws {
        let (store, repository) = coreDataStore()
        let trip = trip()
        store.addTrip(trip)
        let image = try #require(ImageProcessor.prepare(photo(width: 1200, height: 800)))

        #expect(store.setCoverPhoto(image, for: trip.id))
        let coverID = try #require(store.trip(trip.id)?.coverImageID)
        #expect(store.imageData(coverID, thumbnail: false) == image.data)
        #expect(store.imageData(coverID, thumbnail: true) == image.thumbnail)
        #expect(try repository.loadTrips().first?.coverImageID == coverID, "the link is saved, not just kept in memory")
    }

    @Test func replacingOrRemovingTheCoverDeletesTheOldPhoto() throws {
        let (store, _) = coreDataStore()
        let trip = trip()
        store.addTrip(trip)
        let image = try #require(ImageProcessor.prepare(photo(width: 600, height: 400)))

        store.setCoverPhoto(image, for: trip.id)
        let first = try #require(store.trip(trip.id)?.coverImageID)
        store.setCoverPhoto(image, for: trip.id)
        #expect(store.imageData(first, thumbnail: true) == nil)
        #expect(try imageCount() == 1)

        store.setCoverPhoto(nil, for: trip.id)
        #expect(store.trip(trip.id)?.coverImageID == nil)
        #expect(try imageCount() == 0)
    }

    @Test func deletingATripDeletesItsCoverPhoto() throws {
        let (store, _) = coreDataStore()
        let trip = trip()
        store.addTrip(trip)
        let image = try #require(ImageProcessor.prepare(photo(width: 600, height: 400)))
        store.setCoverPhoto(image, for: trip.id)

        store.deleteTrip(trip.id)
        #expect(try imageCount() == 0)
    }

    @Test func aPhotoForATripThatCantBeSavedIsNotLeftBehind() throws {
        let repository = InMemoryTripRepository(trips: [trip()])
        let store = TripStore(repository: repository, clock: FixedClock(now: now))
        let image = try #require(ImageProcessor.prepare(photo(width: 600, height: 400)))

        #expect(!store.setCoverPhoto(image, for: UUID()), "no such trip")
        #expect(repository.images.isEmpty)
    }

    @Test func aPhotoPickedInTheFormIsSavedWithTheNewTrip() async throws {
        let (store, _) = coreDataStore()
        let form = TripFormViewModel(store: store, clock: FixedClock(now: now))
        form.name = "Southern Coast Weekend"
        form.destination = "Galle"
        #expect(form.defaultCover == .galleFort)

        await form.useCoverPhoto(photo(width: 3000, height: 2000))
        #expect(form.hasCustomCover)
        #expect(form.coverThumbnailData != nil)
        #expect(form.save())

        let saved = try #require(store.trips.first)
        #expect(saved.coverImageID != nil)
        #expect(try imageCount() == 1)
    }

    @Test func removingThePhotoInTheEditFormGoesBackToTheDefault() async throws {
        let (store, _) = coreDataStore()
        let trip = trip()
        store.addTrip(trip)
        let image = try #require(ImageProcessor.prepare(photo(width: 600, height: 400)))
        store.setCoverPhoto(image, for: trip.id)

        let form = TripFormViewModel(tripID: trip.id, store: store, clock: FixedClock(now: now))
        #expect(form.hasCustomCover)
        form.removeCoverPhoto()
        #expect(!form.hasCustomCover)
        #expect(form.save())
        #expect(store.trip(trip.id)?.coverImageID == nil)
    }

    @Test func aFileThatIsNotAPhotoShowsAProblem() async {
        let (store, _) = coreDataStore()
        let form = TripFormViewModel(store: store, clock: FixedClock(now: now))
        await form.useCoverPhoto(Data("not a photo".utf8))
        #expect(form.coverProblem != nil)
        #expect(!form.hasCustomCover)
    }

    @Test func theForecastCacheIsSavedWithTheTripAndDeletedWithIt() throws {
        let (store, repository) = coreDataStore()
        let trip = trip()
        store.addTrip(trip)
        let cache = CachedForecast(payload: Data("{}".utf8), location: "6.033,80.217", fetchedAt: now)

        store.saveForecast(cache, for: trip.id)
        #expect(store.cachedForecast(for: trip.id) == cache)

        store.deleteTrip(trip.id)
        #expect(try repository.cachedForecast(for: trip.id) == nil)
        #expect(try persistence.container.viewContext.count(for: ForecastCacheEntity.fetchRequest()) == 0)
    }
}
