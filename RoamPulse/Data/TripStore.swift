import SwiftUI
import Observation

/// In-memory data for the prototype, shared through the environment.
/// Later this is where Core Data reads and writes will go.
@Observable
final class TripStore {
    var trips: [Trip] = []
    var memories: [Memory] = []
    var landmarks: [Landmark] = []
    var weather = SampleData.ellaWeather
    let profile = SampleData.profile
    let me = SampleData.savishka

    init() {
        loadSampleData()
    }

    func loadSampleData() {
        trips = SampleData.trips
        memories = SampleData.memories
        landmarks = SampleData.landmarks
    }

    // MARK: - Lookups

    var activeTrip: Trip? { trips.first { $0.status() == .active } }

    var upcomingTrips: [Trip] {
        trips.filter { $0.status() == .upcoming }.sorted { $0.startDate < $1.startDate }
    }

    var completedTrips: [Trip] {
        trips.filter { $0.status() == .completed }.sorted { $0.startDate > $1.startDate }
    }

    /// The trip quick actions (Add Expense, Record Memory…) apply to.
    var currentTrip: Trip? { activeTrip ?? upcomingTrips.first ?? trips.first }

    var sortedMemories: [Memory] { memories.sorted { $0.date > $1.date } }

    var latestMemory: Memory? { sortedMemories.first }

    func trip(_ id: UUID) -> Trip? { trips.first { $0.id == id } }

    func memory(_ id: UUID) -> Memory? { memories.first { $0.id == id } }

    func memories(inTrip tripID: UUID) -> [Memory] { sortedMemories.filter { $0.tripID == tripID } }

    // MARK: - Trips

    func addTrip(_ trip: Trip) {
        trips.append(trip)
    }

    func deleteTrip(_ id: UUID) {
        trips.removeAll { $0.id == id }
        memories.removeAll { $0.tripID == id }
    }

    // MARK: - Itinerary

    func addActivity(_ activity: Activity, to tripID: UUID) {
        updateTrip(tripID) { $0.activities.append(activity) }
    }

    func toggleDone(_ activityID: UUID, in tripID: UUID) {
        updateTrip(tripID) { trip in
            guard let index = trip.activities.firstIndex(where: { $0.id == activityID }) else { return }
            trip.activities[index].isDone.toggle()
        }
    }

    func markVisited(_ activityID: UUID, in tripID: UUID) {
        updateTrip(tripID) { trip in
            guard let index = trip.activities.firstIndex(where: { $0.id == activityID }) else { return }
            trip.activities[index].isDone = true
        }
    }

    // MARK: - Packing

    func togglePacked(_ itemID: UUID, in tripID: UUID) {
        updateTrip(tripID) { trip in
            guard let index = trip.packing.firstIndex(where: { $0.id == itemID }) else { return }
            trip.packing[index].isPacked.toggle()
        }
    }

    func addPackingItem(_ name: String, category: String, to tripID: UUID) {
        updateTrip(tripID) { $0.packing.append(PackingItem(name: name, category: category)) }
    }

    // MARK: - Expenses

    func addExpense(_ expense: Expense, to tripID: UUID) {
        updateTrip(tripID) { $0.expenses.append(expense) }
    }

    func toggleSettled(_ settlementID: UUID, in tripID: UUID) {
        updateTrip(tripID) { trip in
            guard let index = trip.settlements.firstIndex(where: { $0.id == settlementID }) else { return }
            trip.settlements[index].isSettled.toggle()
        }
    }

    // MARK: - Journal

    func addMemory(_ memory: Memory) {
        memories.append(memory)
    }

    func updateTranscript(_ text: String, for memoryID: UUID) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].transcript = text
        memories[index].transcriptUnavailable = false
    }

    /// Adds a photo to an existing memory, or creates a new photo memory when `memoryID` is nil.
    /// Returns the memory the photo was saved to.
    @discardableResult
    func addPhoto(_ photo: SamplePhoto, landmark: String?, confidence: Double?, sceneTags: [String], to memoryID: UUID?) -> UUID? {
        if let memoryID, let index = memories.firstIndex(where: { $0.id == memoryID }) {
            memories[index].photos.append(photo)
            if memories[index].landmark == nil, let landmark {
                memories[index].landmark = landmark
                memories[index].landmarkConfidence = confidence
            }
            for tag in sceneTags where !memories[index].sceneTags.contains(tag) {
                memories[index].sceneTags.append(tag)
            }
            return memoryID
        }

        guard let trip = currentTrip else { return nil }
        let memory = Memory(
            tripID: trip.id,
            title: landmark ?? "New photo",
            date: DemoClock.now,
            day: trip.dayNumber() ?? 1,
            place: trip.destination,
            transcript: "",
            duration: 0,
            people: [],
            landmark: landmark,
            landmarkConfidence: confidence,
            sceneTags: sceneTags,
            photos: [photo]
        )
        memories.append(memory)
        return memory.id
    }

    // MARK: - Data

    /// Prototype only: "Delete all data" reloads the sample data so the demo keeps working.
    func resetAll() {
        loadSampleData()
    }

    private func updateTrip(_ id: UUID, _ change: (inout Trip) -> Void) {
        guard let index = trips.firstIndex(where: { $0.id == id }) else { return }
        change(&trips[index])
    }
}
