import Foundation
import Observation

/// Journal tab: all memories, newest first, optionally for one trip.
@MainActor
@Observable
final class JournalViewModel {
    private let store: TripStore

    /// nil shows every trip's memories.
    var tripFilter: UUID?
    /// The memory waiting for the user to confirm the delete.
    var memoryPendingDelete: Memory?

    init(store: TripStore) {
        self.store = store
    }

    var memories: [Memory] {
        guard let tripFilter else { return store.sortedMemories }
        return store.memories(inTrip: tripFilter)
    }

    /// Trips that have at least one memory, newest first, for the filter chips.
    var tripsWithMemories: [Trip] {
        let ids = Set(store.memories.map(\.tripID))
        return store.trips.filter { ids.contains($0.id) }.sorted { $0.startDate > $1.startDate }
    }

    var hasNoMemories: Bool { store.memories.isEmpty }

    /// The trip a new memory goes to: the filtered trip, otherwise the current one.
    var tripForNewMemory: UUID? { tripFilter ?? store.currentTrip?.id }

    var canWriteMemory: Bool { !store.trips.isEmpty }

    func tripName(for memory: Memory) -> String {
        store.trip(memory.tripID)?.name ?? ""
    }

    func confirmDelete() {
        guard let memory = memoryPendingDelete else { return }
        store.deleteMemory(memory.id)
        memoryPendingDelete = nil
    }
}

/// New Memory and Edit Memory sheet: text, photos, people, mood and the activity it belongs to.
/// (Voice recording with on-device transcription is added in Increment 14.)
@MainActor
@Observable
final class MemoryFormViewModel {
    /// Most photos one memory can have.
    static let maxPhotos = 10

    /// The memory being edited, or nil for a new one.
    let memoryID: UUID?
    private let store: TripStore
    private let clock: Clock

    var tripID: UUID? {
        didSet {
            guard tripID != oldValue else { return }
            tripDidChange()
        }
    }
    var title = ""
    var text = ""
    var place = ""
    /// When it happened. Limited to the trip's dates; the trip day is worked out from it.
    var date: Date {
        didSet {
            // A different day has different activities.
            if let activity = linkedActivity, activity.day != day {
                linkedActivityID = nil
            }
        }
    }
    var mood: Mood?
    var peopleIDs: Set<UUID> = []
    var linkedActivityID: UUID?
    /// Ticks off the linked activity in the itinerary when the memory is saved.
    var markVisited = true

    /// Photos already saved with the memory (kept unless removed).
    private(set) var existingPhotos: [MemoryPhoto] = []
    /// Photos picked in this form, resized and waiting to be saved.
    private(set) var newPhotos: [PreparedImage] = []
    private(set) var isPreparingPhotos = false
    private(set) var photoProblem: String?

    init(memoryID: UUID? = nil, tripID: UUID? = nil, store: TripStore, clock: Clock) {
        self.memoryID = memoryID
        self.store = store
        self.clock = clock
        date = clock.now

        if let memoryID, let memory = store.memory(memoryID) {
            self.tripID = memory.tripID
            title = memory.title
            text = memory.transcript
            place = memory.place
            date = memory.date
            mood = memory.mood
            peopleIDs = Set(memory.people.map(\.id))
            existingPhotos = memory.photos
            linkedActivityID = store.trip(memory.tripID)?.activities
                .first { Self.label(for: $0) == memory.linkedActivity }?.id
            markVisited = memory.isVisited
        } else {
            self.tripID = tripID ?? store.currentTrip?.id
            if let trip {
                place = trip.mainPlace
                date = Self.clamped(clock.now, to: trip)
            }
        }
    }

    var trip: Trip? { tripID.flatMap(store.trip) }

    /// Active first, then upcoming, then finished trips (newest first).
    var trips: [Trip] {
        let sections = store.sections
        return sections.active + sections.upcoming + sections.completed
    }

    /// The trip's first day at 00:00 to its last day at 23:59.
    var dateRange: ClosedRange<Date> {
        guard let trip else { return clock.now...clock.now }
        let calendar = Calendar.trip
        let start = calendar.startOfDay(for: trip.startDate)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: trip.endDate)) ?? trip.endDate
        return start...max(start, end)
    }

    /// 1-based trip day of `date`.
    var day: Int {
        guard let trip else { return 1 }
        return min(max(Calendar.trip.days(from: trip.startDate, to: date) + 1, 1), trip.dayCount)
    }

    var dayText: String { "Day \(day) • \(date.text("EEE d MMM"))" }

    var members: [Member] { trip?.members ?? [] }

    /// The day's activities, to link the memory to one of them.
    var activitiesOnDay: [Activity] { trip?.activities(onDay: day) ?? [] }

    var linkedActivity: Activity? {
        linkedActivityID.flatMap { id in trip?.activities.first { $0.id == id } }
    }

    /// Places of the day's activities, offered as quick choices.
    var placeSuggestions: [String] {
        var seen = Set<String>()
        let places = activitiesOnDay.map(\.place) + [trip?.mainPlace ?? ""]
        return places.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    func togglePerson(_ member: Member) {
        if peopleIDs.contains(member.id) {
            peopleIDs.remove(member.id)
        } else {
            peopleIDs.insert(member.id)
        }
    }

    /// Picking another trip resets everything that belongs to the old one.
    private func tripDidChange() {
        peopleIDs = []
        linkedActivityID = nil
        if let trip {
            place = trip.mainPlace
            date = Self.clamped(date, to: trip)
        }
    }

    /// The same time of day, moved inside the trip's dates.
    static func clamped(_ date: Date, to trip: Trip) -> Date {
        let calendar = Calendar.trip
        let minutes = calendar.minutesSinceMidnight(date)
        if calendar.days(from: trip.startDate, to: date) < 0 {
            return calendar.date(calendar.startOfDay(for: trip.startDate), atMinutes: minutes)
        }
        if calendar.days(from: date, to: trip.endDate) < 0 {
            return calendar.date(calendar.startOfDay(for: trip.endDate), atMinutes: minutes)
        }
        return date
    }

    /// How a linked activity is saved on the memory, e.g. "Day 2 • 17:30 Nine Arch Bridge viewpoint".
    static func label(for activity: Activity) -> String {
        "Day \(activity.day) • \(activity.timeText) \(activity.title)"
    }

    var photoCount: Int { existingPhotos.count + newPhotos.count }

    var remainingPhotoSlots: Int { max(Self.maxPhotos - photoCount, 0) }

    /// Resizes photos from the photo picker (off the main thread). Nothing is saved until Save.
    func addPhotos(_ files: [Data]) async {
        guard !files.isEmpty else { return }
        isPreparingPhotos = true
        photoProblem = nil
        let allowed = Array(files.prefix(remainingPhotoSlots))
        let prepared = await Task.detached(priority: .userInitiated) {
            allowed.map(ImageProcessor.prepare)
        }.value
        isPreparingPhotos = false
        newPhotos += prepared.compactMap { $0 }
        if prepared.contains(where: { $0 == nil }) {
            photoProblem = "Some files couldn't be opened as photos."
        } else if files.count > allowed.count {
            photoProblem = "A memory can have up to \(Self.maxPhotos) photos."
        }
    }

    func reportPhotoProblem(_ message: String) {
        photoProblem = message
    }

    func removeExistingPhoto(_ photo: MemoryPhoto) {
        existingPhotos.removeAll { $0 == photo }
    }

    func removeNewPhoto(at index: Int) {
        guard newPhotos.indices.contains(index) else { return }
        newPhotos.remove(at: index)
    }

    var isEditing: Bool { memoryID != nil }
    var formTitle: String { isEditing ? "Edit Memory" : "New Memory" }

    private var existingMemory: Memory? { memoryID.flatMap(store.memory) }

    /// A memory needs a trip, a title and something in it: text, a photo or a recording.
    var canSave: Bool { problem == nil && !isPreparingPhotos }

    /// Why Save is disabled, shown under the form.
    var problem: String? {
        if trip == nil { return "Create a trip first. Memories belong to a trip." }
        if title.trimmed.isEmpty { return "Give the memory a title." }
        let hasVoice = existingMemory?.hasVoice ?? false
        if text.trimmed.isEmpty && photoCount == 0 && !hasVoice { return "Write something or add a photo." }
        return nil
    }

    /// Saves the memory and its new photos. Returns false if it couldn't be saved.
    func save() -> Bool {
        guard canSave, let trip else { return false }
        var memory = existingMemory ?? Memory(tripID: trip.id, title: "", date: date, day: day, place: "",
                                              transcript: "", duration: 0, people: [])
        // A mood picked by hand replaces one read from a recording.
        if memory.mood != mood {
            memory.sentiment = nil
        }
        memory.tripID = trip.id
        memory.title = title.trimmed
        memory.transcript = text.trimmed
        if memory.transcriptUnavailable && !text.trimmed.isEmpty {
            memory.transcriptUnavailable = false
        }
        memory.place = place.trimmed.isEmpty ? trip.mainPlace : place.trimmed
        memory.date = date
        memory.day = day
        memory.mood = mood
        memory.people = trip.members.filter { peopleIDs.contains($0.id) }
        memory.photos = existingPhotos
        memory.linkedActivity = linkedActivity.map(Self.label)
        memory.isVisited = linkedActivity != nil && markVisited

        guard store.saveMemory(memory, newPhotos: newPhotos) else { return false }
        if let activity = linkedActivity, markVisited {
            store.markVisited(activity.id, in: trip.id)
        }
        return true
    }
}
