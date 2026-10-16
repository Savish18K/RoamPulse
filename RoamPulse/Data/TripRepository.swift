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
        trips[trip.id] = trip
    }

    func deleteTrip(id: UUID) throws {
        try checkFailure()
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
    }

    private func checkFailure() throws {
        if failSaves { throw RepositoryError.saveFailed }
    }
}
