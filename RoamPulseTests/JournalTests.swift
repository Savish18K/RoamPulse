import CoreData
import Foundation
import Testing
import UIKit
@testable import RoamPulse

/// The journal: writing, editing and deleting memories, their photos in Core Data,
/// linking to an activity, and the Journal tab's trip filter.
@MainActor
struct JournalTests {
    /// Sunday 13 December 2026, 16:40 (Day 2 of the trip below).
    let now = Calendar.trip.date(2026, 12, 13, 16, 40)
    let persistence = PersistenceController(inMemory: true)
    let me = Member(name: "Savishka", colorHex: 0, isMe: true)
    let suu = Member(name: "Suu", colorHex: 1)
    let falls: Activity
    let trip: Trip

    init() {
        falls = Activity(day: 2, title: "Ravana Falls", minutes: 15 * 60, place: "Ella", effort: .moderate, isOutdoor: true)
        var trip = Trip(name: "Hill Country Explorer", destination: "Kandy to Ella",
                        startDate: Calendar.trip.date(2026, 12, 12), endDate: Calendar.trip.date(2026, 12, 15),
                        budget: 0, members: [me, suu], cover: .hillTrain)
        trip.activities = [falls]
        self.trip = trip
    }

    /// A store backed by a real (in-memory) Core Data database, with the trip saved.
    private func makeStore() -> TripStore {
        let store = TripStore(repository: CoreDataTripRepository(context: persistence.container.viewContext),
                              clock: FixedClock(now: now))
        store.addTrip(trip)
        return store
    }

    private func form(_ store: TripStore, memoryID: UUID? = nil) -> MemoryFormViewModel {
        MemoryFormViewModel(memoryID: memoryID, tripID: trip.id, store: store, clock: FixedClock(now: now))
    }

    private func photo() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200), format: format)
            .jpegData(withCompressionQuality: 0.9) { context in
                UIColor.systemGreen.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
            }
    }

    private func count(_ entity: String) throws -> Int {
        try persistence.container.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: entity))
    }

    @Test func aNewMemoryStartsOnTodayOfTheCurrentTrip() {
        let form = form(makeStore())
        #expect(form.trip?.id == trip.id)
        #expect(form.day == 2)
        #expect(form.place == "Ella")
        #expect(form.activitiesOnDay.map(\.title) == ["Ravana Falls"])
        #expect(form.placeSuggestions == ["Ella"])
    }

    @Test func aMemoryNeedsATitleAndSomethingInIt() {
        let form = form(makeStore())
        #expect(!form.canSave)
        form.title = "Waterfall"
        #expect(form.problem == "Write something or add a photo.")
        form.text = "   "
        #expect(!form.canSave, "spaces don't count")
        form.text = "Soaked but worth it."
        #expect(form.canSave)
    }

    @Test func savingAWrittenMemoryKeepsPeopleMoodAndTheLinkedActivity() throws {
        let store = makeStore()
        let form = form(store)
        form.title = "  Ravana Falls in the rain "
        form.text = "Soaked but worth it."
        form.togglePerson(suu)
        form.mood = .positive
        form.linkedActivityID = falls.id
        #expect(form.save())

        let memory = try #require(store.memories.first)
        #expect(memory.title == "Ravana Falls in the rain", "trimmed")
        #expect(memory.people.map(\.name) == ["Suu"])
        #expect(memory.mood == .positive)
        #expect(memory.day == 2)
        #expect(memory.linkedActivity == "Day 2 • 15:00 Ravana Falls")
        #expect(memory.isVisited)
        #expect(store.trip(trip.id)?.activities.first?.isDone == true, "the activity is ticked off in the plan")
    }

    @Test func movingToAnotherDayUnlinksTheActivity() {
        let form = form(makeStore())
        form.linkedActivityID = falls.id
        form.date = Calendar.trip.date(2026, 12, 14, 10)
        #expect(form.day == 3)
        #expect(form.linkedActivityID == nil)
    }

    @Test func theDateStaysInsideTheTrip() {
        let finished = Calendar.trip.date(2026, 12, 20, 9, 30)
        #expect(MemoryFormViewModel.clamped(finished, to: trip) == Calendar.trip.date(2026, 12, 15, 9, 30))
        let early = Calendar.trip.date(2026, 12, 1, 8)
        #expect(MemoryFormViewModel.clamped(early, to: trip) == Calendar.trip.date(2026, 12, 12, 8))
    }

    @Test func photosAreResizedAndSavedWithTheMemory() async throws {
        let store = makeStore()
        let form = form(store)
        form.title = "Blue train"
        await form.addPhotos([photo(), photo(), Data("not a photo".utf8)])
        #expect(form.photoCount == 2)
        #expect(form.photoProblem != nil, "the broken file is reported")
        #expect(form.canSave, "photos alone are enough")
        #expect(form.save())

        let memory = try #require(store.memories.first)
        #expect(memory.photos.count == 2)
        #expect(memory.storedImageIDs.count == 2)
        #expect(try count("StoredImageEntity") == 2)
        #expect(store.imageData(memory.storedImageIDs[0], thumbnail: true) != nil)

        // Loads back the same from Core Data.
        let reloaded = try CoreDataTripRepository(context: persistence.container.viewContext).loadMemories()
        #expect(reloaded.first?.photos == memory.photos)
    }

    @Test func removingAPhotoOrTheMemoryDeletesTheSavedImages() async throws {
        let store = makeStore()
        let create = form(store)
        create.title = "Blue train"
        await create.addPhotos([photo(), photo()])
        #expect(create.save())
        let memory = try #require(store.memories.first)

        let edit = form(store, memoryID: memory.id)
        #expect(edit.existingPhotos.count == 2)
        edit.removeExistingPhoto(memory.photos[0])
        #expect(edit.save())
        #expect(store.memory(memory.id)?.photos == [memory.photos[1]])
        #expect(try count("StoredImageEntity") == 1)

        store.deleteMemory(memory.id)
        #expect(store.memories.isEmpty)
        #expect(try count("StoredImageEntity") == 0)
        #expect(try count("PhotoEntity") == 0)
    }

    @Test func aMemoryHasAtMostTenPhotos() async {
        let form = form(makeStore())
        await form.addPhotos(Array(repeating: photo(), count: 12))
        #expect(form.photoCount == MemoryFormViewModel.maxPhotos)
        #expect(form.remainingPhotoSlots == 0)
        #expect(form.photoProblem != nil)
    }

    @Test func sampleAndPickedPhotosCanBeMixed() throws {
        let store = makeStore()
        let memory = Memory(tripID: trip.id, title: "Mixed", date: now, day: 2, place: "Ella", transcript: "Hi",
                            duration: 0, people: [], photos: [.sample(.nineArchBridge)])
        store.addMemory(memory)
        let image = try #require(ImageProcessor.prepare(photo()))
        #expect(store.saveMemory(memory, newPhotos: [image]))

        let saved = try #require(store.memory(memory.id))
        #expect(saved.photos.count == 2)
        #expect(saved.photos.first == .sample(.nineArchBridge))
    }

    @Test func editingKeepsWhatTheFormDoesntShow() throws {
        let store = makeStore()
        var memory = Memory(tripID: trip.id, title: "Voice note", date: now, day: 2, place: "Ella",
                            transcript: "Recorded on the bridge.", duration: 48, people: [me],
                            mood: .positive, sentiment: 0.7, placeTags: ["Ella"], landmark: "Nine Arch Bridge")
        memory.linkedActivity = MemoryFormViewModel.label(for: falls)
        store.addMemory(memory)

        let edit = form(store, memoryID: memory.id)
        #expect(edit.linkedActivityID == falls.id, "the saved link is found again")
        edit.title = "Blue train"
        #expect(edit.save())

        let saved = try #require(store.memory(memory.id))
        #expect(saved.title == "Blue train")
        #expect(saved.duration == 48, "the recording is kept")
        #expect(saved.landmark == "Nine Arch Bridge")
        #expect(saved.sentiment == 0.7, "mood unchanged, so the read sentiment stays")

        let changeMood = form(store, memoryID: memory.id)
        changeMood.mood = .mixed
        #expect(changeMood.save())
        #expect(store.memory(memory.id)?.sentiment == nil, "a mood picked by hand replaces the read one")
    }

    @Test func theJournalCanShowOneTrip() {
        let store = makeStore()
        var other = trip
        other.id = UUID()
        other.name = "Galle"
        store.addTrip(other)
        store.addMemory(Memory(tripID: trip.id, title: "A", date: now, day: 2, place: "Ella", transcript: "a", duration: 0, people: []))
        store.addMemory(Memory(tripID: other.id, title: "B", date: now.addingTimeInterval(60), day: 2, place: "Galle",
                               transcript: "b", duration: 0, people: []))

        let journal = JournalViewModel(store: store)
        #expect(journal.memories.map(\.title) == ["B", "A"], "newest first")
        #expect(journal.tripsWithMemories.count == 2)
        journal.tripFilter = trip.id
        #expect(journal.memories.map(\.title) == ["A"])
        #expect(journal.tripForNewMemory == trip.id)

        journal.memoryPendingDelete = journal.memories.first
        journal.confirmDelete()
        #expect(store.memories.map(\.title) == ["B"])
    }
}
