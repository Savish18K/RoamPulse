import Foundation
import Observation

/// The app's data in memory, shared by every screen.
///
/// It loads trips and memories from a `TripRepository` (Core Data in the app) and saves every
/// change straight back. A change only appears on screen after it has been saved, so what you
/// see is always what is stored. View models decide *what* to change; the store applies and saves it.
///
/// After signing in, `AppSession` opens the account's own database with `open(repository:user:)`
/// and connects `sync`, which uploads every saved trip change and sends back changes from the cloud
/// through `applyRemote`.
@MainActor
@Observable
final class TripStore {
    private(set) var trips: [Trip] = []
    private(set) var memories: [Memory] = []
    /// The landmarks the Core ML model will know. Sample data until Increment 15.
    var landmarks: [Landmark] = SampleData.landmarks
    /// The signed-in person. Sample values until an account is opened (tests and previews).
    private(set) var profile = SampleData.profile
    /// The signed-in person as a trip member, used when creating a trip.
    private(set) var me = SampleData.me
    /// Set when loading or saving fails. RootView shows it as an alert.
    var errorMessage: String?

    /// Uploads changes made on this iPhone. nil while signed out, and in tests that don't need it.
    var sync: SyncService?

    let clock: Clock
    private var repository: TripRepository

    init(repository: TripRepository, clock: Clock) {
        self.repository = repository
        self.clock = clock
        reload()
    }

    // MARK: - Account

    /// Switches to the signed-in person's own database and shows their trips.
    func open(repository: TripRepository, user: AppUser) {
        self.repository = repository
        updateAccount(user)
        reload()
    }

    /// Updates the name shown on Profile, e.g. once a new account's name has been saved.
    func updateAccount(_ user: AppUser) {
        profile = UserProfile(fullName: user.name, email: user.email)
        me = Member(id: me.id, name: user.firstName, initials: user.initials, colorHex: me.colorHex, isMe: true)
    }

    /// Signed out: forgets the data in memory. The account's database stays on the iPhone for next time.
    func close() {
        sync = nil
        repository = InMemoryTripRepository()
        trips = []
        memories = []
        profile = SampleData.profile
        me = SampleData.me
    }

    func reload() {
        do {
            trips = try repository.loadTrips()
            memories = try repository.loadMemories()
        } catch {
            report(error, failedTo: "load your trips")
        }
    }

    // MARK: - Lookups

    var now: Date { clock.now }

    /// Trips split into Active, Upcoming and Completed.
    var sections: TripSections { trips.sections(at: now) }

    var activeTrip: Trip? { sections.active.first }

    var upcomingTrips: [Trip] { sections.upcoming }

    var completedTrips: [Trip] { sections.completed }

    /// The trip the quick actions (Add Expense, Record Memory…) apply to.
    var currentTrip: Trip? { activeTrip ?? upcomingTrips.first ?? completedTrips.first }

    var sortedMemories: [Memory] { memories.sorted { $0.date > $1.date } }

    var latestMemory: Memory? { sortedMemories.first }

    func trip(_ id: UUID) -> Trip? { trips.first { $0.id == id } }

    /// Trips that have started (active or completed).
    var travelledTrips: [Trip] { trips.filter { $0.status(at: now) != .upcoming } }

    /// Different places where at least one activity was done.
    var placesVisited: Int { Self.placesVisited(in: trips) }

    static func placesVisited(in trips: [Trip]) -> Int {
        Set(trips.flatMap(\.activities).filter(\.isDone).map { $0.place.lowercased() }).count
    }

    func memory(_ id: UUID) -> Memory? { memories.first { $0.id == id } }

    func memories(inTrip tripID: UUID) -> [Memory] { sortedMemories.filter { $0.tripID == tripID } }

    // MARK: - Trips

    // Each change returns false if it couldn't be saved, so a form can stay open.

    @discardableResult
    func addTrip(_ trip: Trip) -> Bool {
        guard save(trip) else { return false }
        trips.append(trip)
        sync?.tripDidChange(from: nil, to: trip)
        return true
    }

    /// Changes one trip and saves it, e.g. `store.updateTrip(id) { $0.name = "Ella weekend" }`.
    /// If saving fails, the change is dropped and an error is shown.
    @discardableResult
    func updateTrip(_ id: UUID, _ change: (inout Trip) -> Void) -> Bool {
        guard let index = trips.firstIndex(where: { $0.id == id }) else { return false }
        let old = trips[index]
        var trip = old
        change(&trip)
        guard trip != old else { return true }
        guard save(trip) else { return false }
        trips[index] = trip
        sync?.tripDidChange(from: old, to: trip)
        return true
    }

    /// Deletes the trip and everything in it, including its journal memories.
    @discardableResult
    func deleteTrip(_ id: UUID) -> Bool {
        let old = trip(id)
        do {
            try repository.deleteTrip(id: id)
            trips.removeAll { $0.id == id }
            memories.removeAll { $0.tripID == id }
            sync?.tripDidChange(from: old, to: nil)
            return true
        } catch {
            report(error, failedTo: "delete the trip")
            return false
        }
    }

    /// Ticks off the activity a photo was linked to.
    func markVisited(_ activityID: UUID, in tripID: UUID) {
        updateTrip(tripID) { trip in
            guard let index = trip.activities.firstIndex(where: { $0.id == activityID }) else { return }
            trip.activities[index].isDone = true
        }
    }

    // MARK: - Cover photo

    /// Saves a photo picked for the trip's cover (replacing and deleting the old one), or removes it with nil.
    @discardableResult
    func setCoverPhoto(_ image: PreparedImage?, for tripID: UUID) -> Bool {
        guard let image else {
            return updateTrip(tripID) { $0.coverImageID = nil }
        }
        do {
            let imageID = try repository.saveImage(image)
            if updateTrip(tripID, { $0.coverImageID = imageID }) {
                return true
            }
            // The trip couldn't be saved, so don't leave the photo behind.
            try? repository.deleteImage(id: imageID)
            return false
        } catch {
            report(error, failedTo: "save the cover photo")
            return false
        }
    }

    /// The saved photo's JPEG data, or its small thumbnail.
    func imageData(_ id: UUID, thumbnail: Bool) -> Data? {
        try? repository.imageData(id: id, thumbnail: thumbnail)
    }

    // MARK: - Changes from the cloud

    // These save straight to the repository and are not passed to `sync`, so a change that came
    // from the cloud is never uploaded again.

    /// Saves a trip as it is in the cloud (new, or changed on another device).
    /// The cover photo is only stored on this iPhone, so the local one is kept.
    func applyRemote(_ remote: Trip) {
        var trip = remote
        let index = trips.firstIndex { $0.id == remote.id }
        if let index {
            trip.coverImageID = trips[index].coverImageID
            guard trip != trips[index] else { return }
        }
        guard save(trip) else { return }
        if let index {
            trips[index] = trip
        } else {
            trips.append(trip)
        }
    }

    /// A trip was deleted on another device.
    func applyRemoteDeletion(_ id: UUID) {
        guard trip(id) != nil else { return }
        do {
            try repository.deleteTrip(id: id)
            trips.removeAll { $0.id == id }
            memories.removeAll { $0.tripID == id }
        } catch {
            report(error, failedTo: "remove a trip deleted on another device")
        }
    }

    // MARK: - Journal

    @discardableResult
    func addMemory(_ memory: Memory) -> Bool {
        guard save(memory) else { return false }
        memories.append(memory)
        return true
    }

    @discardableResult
    func updateMemory(_ id: UUID, _ change: (inout Memory) -> Void) -> Bool {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return false }
        var memory = memories[index]
        change(&memory)
        guard memory != memories[index] else { return true }
        guard save(memory) else { return false }
        memories[index] = memory
        return true
    }

    func updateTranscript(_ text: String, for memoryID: UUID) {
        updateMemory(memoryID) { memory in
            memory.transcript = text
            memory.transcriptUnavailable = false
        }
    }

    /// Adds a photo to an existing memory, or creates a new photo memory when `memoryID` is nil.
    /// Returns the memory the photo was saved to.
    @discardableResult
    func addPhoto(_ photo: SamplePhoto, landmark: String?, confidence: Double?, sceneTags: [String], to memoryID: UUID?) -> UUID? {
        if let memoryID, memory(memoryID) != nil {
            updateMemory(memoryID) { memory in
                memory.photos.append(photo)
                if memory.landmark == nil, let landmark {
                    memory.landmark = landmark
                    memory.landmarkConfidence = confidence
                }
                for tag in sceneTags where !memory.sceneTags.contains(tag) {
                    memory.sceneTags.append(tag)
                }
            }
            return memoryID
        }

        guard let trip = currentTrip else { return nil }
        let memory = Memory(
            tripID: trip.id,
            title: landmark ?? "New photo",
            date: now,
            day: trip.dayNumber(at: now) ?? 1,
            place: trip.mainPlace,
            transcript: "",
            duration: 0,
            people: [],
            landmark: landmark,
            landmarkConfidence: confidence,
            sceneTags: sceneTags,
            photos: [photo]
        )
        addMemory(memory)
        return memory.id
    }

    // MARK: - All data

    /// Settings → Delete all data. Also deletes the trips from the cloud.
    func deleteAllData() {
        let deleted = trips
        do {
            try repository.deleteEverything()
            trips = []
            memories = []
            for trip in deleted {
                sync?.tripDidChange(from: trip, to: nil)
            }
        } catch {
            report(error, failedTo: "delete your data")
        }
    }

    /// Adds the sample trips and memories, with dates around today.
    func loadSampleData() {
        let sample = SampleData.make(now: now)
        for trip in sample.trips { addTrip(trip) }
        for memory in sample.memories { addMemory(memory) }
    }

    // MARK: - Saving

    private func save(_ trip: Trip) -> Bool {
        do {
            try repository.save(trip)
            return true
        } catch {
            report(error, failedTo: "save “\(trip.name)”")
            return false
        }
    }

    private func save(_ memory: Memory) -> Bool {
        do {
            try repository.save(memory)
            return true
        } catch {
            report(error, failedTo: "save the memory")
            return false
        }
    }

    private func report(_ error: Error, failedTo action: String) {
        errorMessage = "Couldn't \(action). \(error.localizedDescription)"
    }
}
