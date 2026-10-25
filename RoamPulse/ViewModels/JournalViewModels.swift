import Foundation
import Observation

@MainActor
@Observable
final class JournalViewModel {
    private let store: TripStore

    // nil = all trips
    var tripFilter: UUID?
    var memoryPendingDelete: Memory?

    init(store: TripStore) {
        self.store = store
    }

    var memories: [Memory] {
        guard let tripFilter else { return store.sortedMemories }
        return store.memories(inTrip: tripFilter)
    }

    var tripsWithMemories: [Trip] {
        let ids = Set(store.memories.map(\.tripID))
        return store.trips.filter { ids.contains($0.id) }.sorted { $0.startDate > $1.startDate }
    }

    var hasNoMemories: Bool { store.memories.isEmpty }

    // Filtered trip, otherwise the current one
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

// New / edit memory sheet
@MainActor
@Observable
final class MemoryFormViewModel {
    static let maxPhotos = 10

    // nil for a new memory
    let memoryID: UUID?
    private let store: TripStore
    private let clock: Clock
    // nil in some tests
    private let recorder: AudioRecording?
    private let voice: VoiceJournalService?
    private let recognizer: LandmarkRecognizing?

    var tripID: UUID? {
        didSet {
            guard tripID != oldValue else { return }
            tripDidChange()
        }
    }
    var title = ""
    var text = ""
    var place = ""
    // Kept inside the trip dates
    var date: Date {
        didSet {
            // Different day so clear the activity
            if let activity = linkedActivity, activity.day != day {
                linkedActivityID = nil
            }
        }
    }
    var mood: Mood?
    var peopleIDs: Set<UUID> = []
    var linkedActivityID: UUID?
    var markVisited = true

    private(set) var existingPhotos: [MemoryPhoto] = []
    // Resized, not saved until Save
    private(set) var newPhotos: [PreparedImage] = []
    private(set) var isPreparingPhotos = false
    private(set) var photoProblem: String?

    // Landmark recognition on the new photos (Vision + my Core ML model)
    private(set) var isRecognising = false
    // The clearest result among the new photos, shown on the form
    private(set) var recognition: RecognitionResult?
    // What gets saved. Only set when the model is sure enough or the user chose it
    private(set) var landmark: String?
    // nil when the user picked the landmark themselves
    private(set) var landmarkConfidence: Double?
    private(set) var sceneTags: [String] = []
    private(set) var recognitionProblem: String?
    // Results per new photo, keyed by its thumbnail
    private var results: [Data: RecognitionResult] = [:]
    private var userChoseLandmark = false
    private var autoLinkedActivityID: UUID?
    private var conflictSettled = false

    // In tmp until Save
    private(set) var newRecording: URL?
    private(set) var newRecordingDuration = 0
    private(set) var removesSavedRecording = false
    private(set) var recordingProblem: String?

    init(memoryID: UUID? = nil, tripID: UUID? = nil, activityID: UUID? = nil, store: TripStore, clock: Clock,
         recorder: AudioRecording? = nil, voice: VoiceJournalService? = nil,
         recognizer: LandmarkRecognizing? = nil) {
        self.memoryID = memoryID
        self.recognizer = recognizer
        self.store = store
        self.clock = clock
        self.recorder = recorder
        self.voice = voice
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
            landmark = memory.landmark
            landmarkConfidence = memory.landmarkConfidence
            sceneTags = memory.sceneTags
            // A landmark already saved isn't replaced by what new photos show
            userChoseLandmark = memory.landmark != nil
        } else {
            self.tripID = tripID ?? store.currentTrip?.id
            if let trip {
                place = trip.mainPlace
                date = Self.clamped(clock.now, to: trip)
            }
            // Opened from an arrival alert or the map: link the activity straight away
            if let trip, let activity = trip.activities.first(where: { $0.id == activityID }) {
                if activity.day != day {
                    date = WeatherAdvisor.startDate(of: activity, in: trip)
                }
                linkedActivityID = activity.id
                place = activity.place.isEmpty ? trip.mainPlace : activity.place
            }
        }
    }

    var trip: Trip? { tripID.flatMap(store.trip) }

    var trips: [Trip] {
        let sections = store.sections
        return sections.active + sections.upcoming + sections.completed
    }

    var dateRange: ClosedRange<Date> {
        guard let trip else { return clock.now...clock.now }
        let calendar = Calendar.trip
        let start = calendar.startOfDay(for: trip.startDate)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: trip.endDate)) ?? trip.endDate
        return start...max(start, end)
    }

    // Starts at 1
    var day: Int {
        guard let trip else { return 1 }
        return min(max(Calendar.trip.days(from: trip.startDate, to: date) + 1, 1), trip.dayCount)
    }

    var dayText: String { "Day \(day) • \(date.text("EEE d MMM"))" }

    var members: [Member] { trip?.members ?? [] }

    var activitiesOnDay: [Activity] { trip?.activities(onDay: day) ?? [] }

    var linkedActivity: Activity? {
        linkedActivityID.flatMap { id in trip?.activities.first { $0.id == id } }
    }

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

    // Reset things from the old trip
    private func tripDidChange() {
        peopleIDs = []
        linkedActivityID = nil
        if let trip {
            place = trip.mainPlace
            date = Self.clamped(date, to: trip)
        }
    }

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

    // e.g. "Day 2 • 17:30 Nine Arch Bridge viewpoint"
    static func label(for activity: Activity) -> String {
        "Day \(activity.day) • \(activity.timeText) \(activity.title)"
    }

    var photoCount: Int { existingPhotos.count + newPhotos.count }

    var remainingPhotoSlots: Int { max(Self.maxPhotos - photoCount, 0) }

    // Resized off the main thread
    func addPhotos(_ files: [Data]) async {
        guard !files.isEmpty else { return }
        isPreparingPhotos = true
        photoProblem = nil
        let allowed = Array(files.prefix(remainingPhotoSlots))
        let prepared = await Task.detached(priority: .userInitiated) {
            allowed.map(ImageProcessor.prepare)
        }.value
        isPreparingPhotos = false
        let added = prepared.compactMap { $0 }
        newPhotos += added
        if prepared.contains(where: { $0 == nil }) {
            photoProblem = "Some files couldn't be opened as photos."
        } else if files.count > allowed.count {
            photoProblem = "A memory can have up to \(Self.maxPhotos) photos."
        }
        await recognise(added)
    }

    // Landmark recognition

    var landmarkInfo: LandmarkInfo? { landmark.flatMap(LandmarkCatalogue.info) }

    var showsLandmarkSection: Bool { isRecognising || recognition != nil || landmark != nil || recognitionProblem != nil }

    // The model wasn't sure (or saw no landmark), so the user is asked instead of saving a guess
    var needsLandmarkConfirmation: Bool { landmark == nil && !userChoseLandmark && recognition != nil }

    var landmarkChosenByUser: Bool { landmark != nil && landmarkConfidence == nil }

    // A different landmark named in the title or text, e.g. the note says Sigiriya but the photo looks like Dambulla
    var conflictingLandmark: LandmarkInfo? {
        guard let landmark, !conflictSettled,
              let named = LandmarkCatalogue.mentioned(in: "\(title) \(text)"), named.name != landmark else { return nil }
        return named
    }

    func chooseLandmark(_ name: String) {
        userChoseLandmark = true
        conflictSettled = true
        setLandmark(name, confidence: nil)
    }

    func rejectLandmark() {
        userChoseLandmark = true
        recognition = nil
        setLandmark(nil, confidence: nil)
    }

    func keepPhotoLandmark() {
        conflictSettled = true
    }

    private func recognise(_ photos: [PreparedImage]) async {
        guard let recognizer, !photos.isEmpty else { return }
        isRecognising = true
        recognitionProblem = nil
        for photo in photos {
            do {
                results[photo.thumbnail] = try await recognizer.recognize(photo.data)
            } catch {
                recognitionProblem = error.localizedDescription
            }
        }
        isRecognising = false
        refreshLandmark()
    }

    private func refreshLandmark() {
        let current = newPhotos.compactMap { results[$0.thumbnail] }
        // A photo of a landmark wins over one that shows "Other"
        recognition = current.max { Self.score($0) < Self.score($1) }
        var tags = existingMemory?.sceneTags ?? []
        for tag in current.flatMap(\.sceneTags) where !tags.contains(tag) {
            tags.append(tag)
        }
        sceneTags = Array(tags.prefix(6))

        guard !userChoseLandmark else { return }
        if let recognition, recognition.isConfident, let top = recognition.top {
            setLandmark(top.name, confidence: top.confidence)
        } else {
            setLandmark(nil, confidence: nil)
        }
    }

    private static func score(_ result: RecognitionResult) -> Double {
        result.isOther ? -1 : result.top?.confidence ?? -1
    }

    private func setLandmark(_ name: String?, confidence: Double?) {
        landmark = name
        landmarkConfidence = name == nil ? nil : confidence
        // Link the planned activity at this landmark, unless the user linked one themselves
        if linkedActivityID == nil || linkedActivityID == autoLinkedActivityID {
            let activity = name.flatMap { LandmarkCatalogue.activity(for: $0, in: activitiesOnDay) }
            linkedActivityID = activity?.id
            autoLinkedActivityID = activity?.id
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
        refreshLandmark()
    }

    // Voice recording

    var canRecord: Bool { recorder != nil }
    var isRecording: Bool { recorder?.isRecording ?? false }
    var recordingElapsed: Int { Int(recorder?.elapsed ?? 0) }
    var recordingLevels: [Double] { recorder?.levels ?? [] }

    var hasSavedRecording: Bool {
        (existingMemory?.hasVoice ?? false) && !removesSavedRecording && newRecording == nil
    }

    var hasRecording: Bool { newRecording != nil || hasSavedRecording }

    // Seconds
    var recordingDuration: Int { newRecording != nil ? newRecordingDuration : (existingMemory?.duration ?? 0) }

    // New take if there is one, otherwise the saved one
    var recordingURL: URL? {
        if let newRecording { return newRecording }
        guard hasSavedRecording, let memory = existingMemory else { return nil }
        return store.recordingURL(for: memory)
    }

    func startRecording() async {
        guard let recorder, !recorder.isRecording else { return }
        recordingProblem = nil
        guard await recorder.requestPermission() else {
            recordingProblem = RecordingError.microphoneDenied.errorDescription
            return
        }
        do {
            try recorder.start()
        } catch {
            recordingProblem = error.localizedDescription
        }
    }

    func stopRecording() {
        guard let recorder, recorder.isRecording else { return }
        let seconds = Int(recorder.elapsed.rounded())
        guard let file = recorder.stop() else { return }
        // New take replaces the old one
        if let previous = newRecording {
            try? FileManager.default.removeItem(at: previous)
        }
        newRecording = file
        newRecordingDuration = max(seconds, 1)
    }

    // New ones are deleted now, saved ones on Save
    func removeRecording() {
        if let newRecording {
            try? FileManager.default.removeItem(at: newRecording)
            self.newRecording = nil
            newRecordingDuration = 0
        } else if existingMemory?.hasVoice == true {
            removesSavedRecording = true
        }
    }

    func discardUnsavedRecording() {
        recorder?.discard()
        if let newRecording {
            try? FileManager.default.removeItem(at: newRecording)
        }
        newRecording = nil
    }

    var isEditing: Bool { memoryID != nil }
    var formTitle: String { isEditing ? "Edit Memory" : "New Memory" }

    private var existingMemory: Memory? { memoryID.flatMap(store.memory) }

    // e.g. "Voice memory • 17:52"
    var automaticTitle: String { "Voice memory • \(date.text("HH:mm"))" }

    var canSave: Bool { problem == nil && !isPreparingPhotos }

    // Shown under the form
    var problem: String? {
        if trip == nil { return "Create a trip first. Memories belong to a trip." }
        let hasRecording = hasRecording || isRecording
        if title.trimmed.isEmpty && !hasRecording { return "Give the memory a title." }
        if text.trimmed.isEmpty && photoCount == 0 && !hasRecording { return "Write something, record or add a photo." }
        return nil
    }

    // New recordings get transcribed in the background after saving
    func save() -> Bool {
        if isRecording {
            stopRecording()
        }
        guard canSave, let trip else { return false }
        let existing = existingMemory
        var memory = existing ?? Memory(tripID: trip.id, title: "", date: date, day: day, place: "",
                                        transcript: "", duration: 0, people: [])
        let previousText = existing?.transcript ?? ""

        memory.tripID = trip.id
        memory.title = title.trimmed.isEmpty ? automaticTitle : title.trimmed
        memory.place = place.trimmed.isEmpty ? trip.mainPlace : place.trimmed
        memory.date = date
        memory.day = day
        memory.people = trip.members.filter { peopleIDs.contains($0.id) }
        memory.photos = existingPhotos
        memory.linkedActivity = linkedActivity.map(Self.label)
        memory.isVisited = linkedActivity != nil && markVisited
        memory.landmark = landmark
        memory.landmarkConfidence = landmarkConfidence
        memory.sceneTags = sceneTags
        memory.transcript = text.trimmed
        if memory.transcriptUnavailable && !text.trimmed.isEmpty {
            memory.transcriptUnavailable = false
        }

        // Picked by hand, so no sentiment
        if mood != existing?.mood {
            memory.mood = mood
            memory.sentiment = nil
        }

        // Move a new take into the recordings folder
        var keptFile: String?
        if let newRecording {
            do {
                keptFile = try store.keepRecording(newRecording, for: memory.id)
            } catch {
                recordingProblem = "The recording couldn't be saved. \(error.localizedDescription)"
                return false
            }
            self.newRecording = nil
            memory.audioFileName = keptFile
            memory.duration = newRecordingDuration
            memory.transcriptUnavailable = false
            // Old transcript goes with the old recording unless it was edited
            if existing?.hasVoice == true && text.trimmed == previousText {
                memory.transcript = ""
            }
        }
        // Only delete the file once the memory is saved
        var removedFile: String?
        if keptFile == nil && removesSavedRecording {
            removedFile = memory.audioFileName
            memory.audioFileName = nil
            memory.duration = 0
        }

        // Run the NL analysis again on new text
        if memory.hasText && memory.transcript != previousText {
            JournalAnalyzer.apply(JournalAnalyzer.analyse(memory.transcript), text: memory.transcript, to: &memory, trip: trip)
        }

        guard store.saveMemory(memory, newPhotos: newPhotos) else {
            if existing == nil { store.deleteRecording(named: keptFile) }
            return false
        }
        store.deleteRecording(named: removedFile)
        if let activity = linkedActivity, markVisited {
            store.markVisited(activity.id, in: trip.id)
        }
        if keptFile != nil && !memory.hasText, let voice {
            let id = memory.id
            Task { await voice.transcribe(id) }
        }
        return true
    }
}
