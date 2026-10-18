import Foundation

/// Loads and saves trips and journal memories.
///
/// Everything above this layer works with plain structs and never touches Core Data directly.
/// The app uses `CoreDataTripRepository`; tests and previews use `InMemoryTripRepository`.
protocol TripRepository {
    func loadTrips() throws -> [Trip]
    /// Inserts the trip, or updates it if one with the same id is already saved.
    /// Its members, activities, packing items, expenses and payments are saved with it.
    func save(_ trip: Trip) throws
    /// Also deletes the trip's memories.
    func deleteTrip(id: UUID) throws

    func loadMemories() throws -> [Memory]
    func save(_ memory: Memory) throws
    func deleteMemory(id: UUID) throws

    func deleteEverything() throws

    /// Saves a photo that isn't linked to anything yet and returns its id.
    /// It is linked by setting `trip.coverImageID` to that id and saving the trip.
    func saveImage(_ image: PreparedImage) throws -> UUID
    /// The full-size JPEG, or the small thumbnail. nil if there is no image with that id.
    func imageData(id: UUID, thumbnail: Bool) throws -> Data?
    func deleteImage(id: UUID) throws
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

// MARK: - InMemoryTripRepository

/// Keeps everything in dictionaries; nothing is written to disk. Used by tests and previews.
final class InMemoryTripRepository: TripRepository {
    private var trips: [UUID: Trip] = [:]
    private var memories: [UUID: Memory] = [:]
    private(set) var images: [UUID: PreparedImage] = [:]

    /// Set to true in a test to make saving fail, to check how errors are handled.
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
        // Like Core Data, a replaced or removed cover photo is deleted.
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
        memories = memories.filter { $0.value.tripID != id }
    }

    func loadMemories() throws -> [Memory] {
        memories.values.sorted { $0.date > $1.date }
    }

    func save(_ memory: Memory) throws {
        try checkFailure()
        guard trips[memory.tripID] != nil else { throw RepositoryError.tripNotFound }
        memories[memory.id] = memory
    }

    func deleteMemory(id: UUID) throws {
        try checkFailure()
        memories[id] = nil
    }

    func deleteEverything() throws {
        try checkFailure()
        trips = [:]
        memories = [:]
        images = [:]
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

    private func checkFailure() throws {
        if failSaves { throw RepositoryError.saveFailed }
    }
}
