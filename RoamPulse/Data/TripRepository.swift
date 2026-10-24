import Foundation

// Plain structs in and out, Core Data in the app and an in-memory version for tests
protocol TripRepository {
    func loadTrips() throws -> [Trip]
    // Insert or update, saves all the trip's child items too
    func save(_ trip: Trip) throws
    func deleteTrip(id: UUID) throws

    func loadMemories() throws -> [Memory]
    func save(_ memory: Memory) throws
    func deleteMemory(id: UUID) throws

    func deleteEverything() throws

    // Saved first and then linked through trip.coverImageID
    func saveImage(_ image: PreparedImage) throws -> UUID
    func imageData(id: UUID, thumbnail: Bool) throws -> Data?
    func deleteImage(id: UUID) throws

    // Last forecast is kept for offline use
    func saveForecast(_ forecast: CachedForecast, for tripID: UUID) throws
    func cachedForecast(for tripID: UUID) throws -> CachedForecast?
}

struct CachedForecast: Equatable {
    var payload: Data
    // e.g. "6.8667,81.0466"
    var location: String
    var fetchedAt: Date
}

enum RepositoryError: LocalizedError {
    case tripNotFound
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .tripNotFound: "The trip for this memory no longer exists."
        case .saveFailed: "The change couldn't be saved."
        }
    }
}

// In-memory version for tests and previews
final class InMemoryTripRepository: TripRepository {
    private var trips: [UUID: Trip] = [:]
    private var memories: [UUID: Memory] = [:]
    private(set) var images: [UUID: PreparedImage] = [:]
    private(set) var forecasts: [UUID: CachedForecast] = [:]

    // Tests set this to check error handling
    var failSaves = false

    init(trips: [Trip] = [], memories: [Memory] = []) {
        for trip in trips { self.trips[trip.id] = trip }
        for memory in memories { self.memories[memory.id] = memory }
    }

    func loadTrips() throws -> [Trip] {
        trips.values.sorted { $0.startDate < $1.startDate }
    }

    func save(_ trip: Trip) throws {
        try checkFailure()
        // Same as Core Data, old cover is removed
        if let oldCover = trips[trip.id]?.coverImageID, oldCover != trip.coverImageID {
            images[oldCover] = nil
        }
        trips[trip.id] = trip
    }

    func deleteTrip(id: UUID) throws {
        try checkFailure()
        if let cover = trips[id]?.coverImageID {
            images[cover] = nil
        }
        trips[id] = nil
        forecasts[id] = nil
        for memory in memories.values where memory.tripID == id {
            memory.storedImageIDs.forEach { images[$0] = nil }
        }
        memories = memories.filter { $0.value.tripID != id }
    }

    func loadMemories() throws -> [Memory] {
        memories.values.sorted { $0.date > $1.date }
    }

    func save(_ memory: Memory) throws {
        try checkFailure()
        guard trips[memory.tripID] != nil else { throw RepositoryError.tripNotFound }
        // Same as Core Data, removed photos are deleted
        let removed = Set(memories[memory.id]?.storedImageIDs ?? []).subtracting(memory.storedImageIDs)
        removed.forEach { images[$0] = nil }
        memories[memory.id] = memory
    }

    func deleteMemory(id: UUID) throws {
        try checkFailure()
        memories[id]?.storedImageIDs.forEach { images[$0] = nil }
        memories[id] = nil
    }

    func deleteEverything() throws {
        try checkFailure()
        trips = [:]
        memories = [:]
        images = [:]
        forecasts = [:]
    }

    func saveImage(_ image: PreparedImage) throws -> UUID {
        try checkFailure()
        let id = UUID()
        images[id] = image
        return id
    }

    func imageData(id: UUID, thumbnail: Bool) throws -> Data? {
        images[id].map { thumbnail ? $0.thumbnail : $0.data }
    }

    func deleteImage(id: UUID) throws {
        images[id] = nil
    }

    func saveForecast(_ forecast: CachedForecast, for tripID: UUID) throws {
        try checkFailure()
        guard trips[tripID] != nil else { throw RepositoryError.tripNotFound }
        forecasts[tripID] = forecast
    }

    func cachedForecast(for tripID: UUID) throws -> CachedForecast? {
        forecasts[tripID]
    }

    private func checkFailure() throws {
        if failSaves { throw RepositoryError.saveFailed }
    }
}
