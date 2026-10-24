import Foundation
import Observation

// Shared app data, every change is saved to the repository straight away and then synced
@MainActor
@Observable
final class TripStore {
    private(set) var trips: [Trip] = []
    private(set) var memories: [Memory] = []
    // Sample data until the Core ML model is added
    var landmarks: [Landmark] = SampleData.landmarks
    private(set) var profile = SampleData.profile
    private(set) var me = SampleData.me
    // nil when signed out
    private(set) var accountID: String?
    // Shown as an alert in RootView
    var errorMessage: String?

    // nil when signed out
    var sync: SyncService?

    let clock: Clock
    private var repository: TripRepository
    private(set) var recordings = RecordingFiles.temporary

    init(repository: TripRepository, clock: Clock) {
        self.repository = repository
        self.clock = clock
        reload()
    }

    func open(repository: TripRepository, user: AppUser) {
        self.repository = repository
        recordings = .forAccount(user.uid)
        updateAccount(user)
        reload()
    }

    func updateAccount(_ user: AppUser) {
        accountID = user.uid
        profile = UserProfile(fullName: user.name, email: user.email)
        me = Member(id: me.id, name: user.firstName, initials: user.initials, colorHex: me.colorHex, isMe: true,
                    userUID: user.uid)
    }

    // Database stays on the phone for next time
    func close() {
        sync = nil
        repository = InMemoryTripRepository()
        trips = []
        memories = []
        profile = SampleData.profile
        me = SampleData.me
        accountID = nil
        recordings = .temporary
    }

    func reload() {
        do {
            trips = try repository.loadTrips()
            memories = try repository.loadMemories()
        } catch {
            report(error, failedTo: "load your trips")
        }
    }

    var now: Date { clock.now }

    var sections: TripSections { trips.sections(at: now) }

    var activeTrip: Trip? { sections.active.first }

    var upcomingTrips: [Trip] { sections.upcoming }

    var completedTrips: [Trip] { sections.completed }

    // Trip used for the quick actions
    var currentTrip: Trip? { activeTrip ?? upcomingTrips.first ?? completedTrips.first }

    var sortedMemories: [Memory] { memories.sorted { $0.date > $1.date } }

    var latestMemory: Memory? { sortedMemories.first }

    func trip(_ id: UUID) -> Trip? { trips.first { $0.id == id } }

    var travelledTrips: [Trip] { trips.filter { $0.status(at: now) != .upcoming } }

    var placesVisited: Int { Self.placesVisited(in: trips) }

    // Static so it can be used off the main actor
    nonisolated static func placesVisited(in trips: [Trip]) -> Int {
        Set(trips.flatMap(\.activities).filter(\.isDone).map { $0.place.lowercased() }).count
    }

    func memory(_ id: UUID) -> Memory? { memories.first { $0.id == id } }

    func memories(inTrip tripID: UUID) -> [Memory] { sortedMemories.filter { $0.tripID == tripID } }

    // These return false if saving failed so the form can stay open

    @discardableResult
    func addTrip(_ trip: Trip) -> Bool {
        let trip = claimed(trip)
        guard save(trip) else { return false }
        trips.append(trip)
        sync?.tripDidChange(from: nil, to: trip)
        return true
    }

    // e.g. store.updateTrip(id) { $0.name = "Ella weekend" }
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

    // For a shared trip this just leaves it, others keep it
    @discardableResult
    func deleteTrip(_ id: UUID) -> Bool {
        let old = trip(id)
        do {
            try repository.deleteTrip(id: id)
            trips.removeAll { $0.id == id }
            removeMemories { $0.tripID == id }
            if let old {
                uploadRemoval(of: old)
            }
            return true
        } catch {
            report(error, failedTo: "delete the trip")
            return false
        }
    }

    func markVisited(_ activityID: UUID, in tripID: UUID) {
        updateTrip(tripID) { trip in
            guard let index = trip.activities.firstIndex(where: { $0.id == activityID }) else { return }
            trip.activities[index].isDone = true
        }
    }

    // Old trips without an owner, or no one signed in, count as owner too
    func isOwner(of trip: Trip) -> Bool {
        trip.ownerUID == nil || accountID == nil || trip.ownerUID == accountID
    }

    private func claimed(_ trip: Trip) -> Trip {
        guard let accountID else { return trip }
        var trip = trip
        if trip.ownerUID == nil {
            trip.ownerUID = accountID
        }
        if !trip.memberUIDs.contains(accountID) {
            trip.memberUIDs.append(accountID)
        }
        for index in trip.members.indices where trip.members[index].isMe && trip.members[index].userUID == nil {
            trip.members[index].userUID = accountID
        }
        return trip
    }

    // Owner deletes it for everyone, others just leave
    private func uploadRemoval(of trip: Trip) {
        if isOwner(of: trip) {
            sync?.tripDidChange(from: trip, to: nil)
        } else {
            sync?.leaveTrip(trip)
        }
    }

    func cachedForecast(for tripID: UUID) -> CachedForecast? {
        try? repository.cachedForecast(for: tripID)
    }

    // Only needed offline, so no alert if it fails
    func saveForecast(_ forecast: CachedForecast, for tripID: UUID) {
        try? repository.saveForecast(forecast, for: tripID)
    }

    // Pass nil to remove the cover
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
            // Don't leave the photo behind
            try? repository.deleteImage(id: imageID)
            return false
        } catch {
            report(error, failedTo: "save the cover photo")
            return false
        }
    }

    func imageData(_ id: UUID, thumbnail: Bool) -> Data? {
        try? repository.imageData(id: id, thumbnail: thumbnail)
    }

    // Changes from the cloud are saved directly and not sent back to sync

    // Cover photo is local only so keep ours
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

    func applyRemoteDeletion(_ id: UUID) {
        guard trip(id) != nil else { return }
        do {
            try repository.deleteTrip(id: id)
            trips.removeAll { $0.id == id }
            removeMemories { $0.tripID == id }
        } catch {
            report(error, failedTo: "remove a trip deleted on another device")
        }
    }

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

    // Photos are saved first, and deleted again if the memory fails to save
    @discardableResult
    func saveMemory(_ memory: Memory, newPhotos: [PreparedImage]) -> Bool {
        var memory = memory
        var savedImageIDs: [UUID] = []
        do {
            for image in newPhotos {
                savedImageIDs.append(try repository.saveImage(image))
            }
        } catch {
            savedImageIDs.forEach { try? repository.deleteImage(id: $0) }
            report(error, failedTo: "save the photos")
            return false
        }
        memory.photos += savedImageIDs.map(MemoryPhoto.stored)

        let saved = self.memory(memory.id) == nil ? addMemory(memory) : updateMemory(memory.id) { $0 = memory }
        if !saved {
            savedImageIDs.forEach { try? repository.deleteImage(id: $0) }
        }
        return saved
    }

    @discardableResult
    func deleteMemory(_ id: UUID) -> Bool {
        do {
            try repository.deleteMemory(id: id)
            removeMemories { $0.id == id }
            return true
        } catch {
            report(error, failedTo: "delete the memory")
            return false
        }
    }

    // Recordings are files so delete them here

    func recordingURL(for memory: Memory) -> URL? {
        guard let fileName = memory.audioFileName, recordings.exists(fileName) else { return nil }
        return recordings.url(for: fileName)
    }

    func keepRecording(_ file: URL, for memoryID: UUID) throws -> String {
        try recordings.keep(file, for: memoryID)
    }

    func deleteRecording(named fileName: String?) {
        recordings.delete(fileName)
    }

    private func removeMemories(where shouldRemove: (Memory) -> Bool) {
        for memory in memories where shouldRemove(memory) {
            recordings.delete(memory.audioFileName)
        }
        memories.removeAll(where: shouldRemove)
    }

    func updateTranscript(_ text: String, for memoryID: UUID) {
        updateMemory(memoryID) { memory in
            memory.transcript = text
            memory.transcriptUnavailable = false
        }
    }

    // nil memoryID creates a new photo memory
    @discardableResult
    func addPhoto(_ photo: SamplePhoto, landmark: String?, confidence: Double?, sceneTags: [String], to memoryID: UUID?) -> UUID? {
        if let memoryID, memory(memoryID) != nil {
            updateMemory(memoryID) { memory in
                memory.photos.append(.sample(photo))
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
            photos: [.sample(photo)]
        )
        addMemory(memory)
        return memory.id
    }

    // Also removes the trips from the cloud
    func deleteAllData() {
        let deleted = trips
        do {
            try repository.deleteEverything()
            trips = []
            removeMemories { _ in true }
            for trip in deleted {
                uploadRemoval(of: trip)
            }
        } catch {
            report(error, failedTo: "delete your data")
        }
    }

    // Adds today's NIBM test trip, or returns the one already added today
    @discardableResult
    func addNIBMTrip() -> UUID? {
        if let existing = trips.first(where: { $0.name == SampleData.nibmTripName && $0.dayNumber(at: now) != nil }) {
            return existing.id
        }
        let trip = SampleData.nibmTrip(now: now)
        return addTrip(trip) ? trip.id : nil
    }

    func loadSampleData() {
        let sample = SampleData.make(now: now)
        for trip in sample.trips { addTrip(trip) }
        for memory in sample.memories { addMemory(memory) }
    }

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
