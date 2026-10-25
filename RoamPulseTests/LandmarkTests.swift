import Foundation
import Testing
import UIKit
@testable import RoamPulse

// Landmark recognition: reading the model's output, the catalogue, the memory form's
// confirm flow, and the real trained model on photos it never saw in training
@MainActor
struct LandmarkTests {
    // Sun 13 Dec 2026, 17:50 (day 2 of the trip below)
    let now = Calendar.trip.date(2026, 12, 13, 17, 50)
    let bridge = Activity(day: 2, title: "Nine Arch Bridge viewpoint", minutes: 17 * 60 + 30, place: "Demodara",
                          effort: .moderate, isOutdoor: true)
    let trip: Trip

    init() {
        var trip = Trip(name: "Hill Country", destination: "Kandy to Ella", startDate: Calendar.trip.date(2026, 12, 12),
                        endDate: Calendar.trip.date(2026, 12, 15), budget: 0, members: [SampleData.me], cover: .hillTrain)
        trip.activities = [bridge,
                           Activity(day: 3, title: "Little Adam's Peak hike", minutes: 6 * 60, place: "Ella", effort: .high),
                           Activity(day: 4, title: "Sri Dalada Maligawa", minutes: 10 * 60, place: "Kandy", effort: .low)]
        self.trip = trip
    }

    private func result(_ labels: [(String, Double)], scenes: [String] = [], threshold: Double = 0.7) -> RecognitionResult {
        RecognitionResult(labels: labels.map { (name: $0.0, confidence: $0.1) },
                          scenes: scenes.map { (name: $0, confidence: 0.8) }, threshold: threshold)
    }

    // A plain JPEG standing in for a photo from the library
    private func photo(_ color: UIColor = .systemGreen) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600), format: format)
            .jpegData(withCompressionQuality: 0.9) { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
            }
    }

    private func makeForm(_ recognizer: FakeLandmarkRecognizer, store: TripStore? = nil) -> (MemoryFormViewModel, TripStore) {
        let store = store ?? TripStore(repository: InMemoryTripRepository(trips: [trip]), clock: FixedClock(now: now))
        let form = MemoryFormViewModel(tripID: trip.id, store: store, clock: FixedClock(now: now), recognizer: recognizer)
        form.title = "At the bridge"
        return (form, store)
    }

    @Test func theTopThreeGuessesAndTidyTagsAreKept() {
        let recognition = result([("Other", 0.05), ("Nine Arch Bridge", 0.82), ("Lotus Tower", 0.08), ("Gal Vihara", 0.05)],
                                 scenes: ["bridge", "structure", "mountain_range"])
        #expect(recognition.candidates.map(\.name) == ["Nine Arch Bridge", "Lotus Tower", "Other"])
        #expect(recognition.sceneTags == ["Bridge", "Mountain Range"], "general labels like structure are dropped")
        #expect(recognition.isConfident)
    }

    @Test func onlySureLandmarkGuessesAreConfident() {
        #expect(!result([("Nine Arch Bridge", 0.64), ("Lotus Tower", 0.3)]).isConfident, "below the threshold")
        #expect(result([("Nine Arch Bridge", 0.64)], threshold: 0.6).isConfident, "the model's own threshold is used")
        let other = result([("Other", 0.91), ("Gal Vihara", 0.06)])
        #expect(!other.isConfident)
        #expect(other.isOther)
        #expect(other.suggestions.map(\.name) == ["Gal Vihara"], "Other is never offered as a landmark")
    }

    @Test func otherNamesForALandmarkAreRecognised() {
        #expect(LandmarkCatalogue.mentioned(in: "Morning puja at the Sri Dalada Maligawa")?.name == "Temple of the Tooth")
        #expect(LandmarkCatalogue.mentioned(in: "Climbed Adam's Peak overnight")?.name == "Sri Pada (Adam's Peak)")
        #expect(LandmarkCatalogue.mentioned(in: "Dinner in Ella town") == nil)
        #expect(LandmarkCatalogue.activity(for: "Temple of the Tooth", in: trip.activities)?.day == 4)
        #expect(LandmarkCatalogue.activity(for: "Nine Arch Bridge", in: trip.activities)?.id == bridge.id)
    }

    @Test func theCatalogueMatchesTheModelLabels() throws {
        let names = LandmarkCatalogue.all.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(!names.contains(RecognitionResult.otherLabel))
        let labels = try modelLabels()
        #expect(Set(labels) == Set(names + [RecognitionResult.otherLabel]), "every class has a catalogue entry")
    }

    @Test func eachLandmarkShowsWhatWasDoneThere() throws {
        var recognised = Memory(tripID: trip.id, title: "Bridge", date: now, day: 2, place: "Ella", transcript: "",
                                duration: 0, people: [])
        recognised.landmark = "Nine Arch Bridge"
        recognised.landmarkConfidence = 0.91
        recognised.photos = [.sample(.nineArchBridge), .sample(.blueTrainBridge)]
        var chosen = recognised
        chosen.id = UUID()
        chosen.landmark = "Gal Vihara"
        chosen.landmarkConfidence = nil
        let spoken = Memory(tripID: trip.id, title: "Voice", date: now, day: 2, place: "Ella",
                            transcript: "We should see Sigiriya next year", duration: 30, people: [])

        let landmarks = LandmarkCatalogue.landmarks(memories: [recognised, chosen, spoken], trips: [trip], now: now)
        let byName = Dictionary(uniqueKeysWithValues: landmarks.map { ($0.name, $0) })
        #expect(landmarks.count == LandmarkCatalogue.all.count)
        #expect(byName["Nine Arch Bridge"]?.status == .recognised(confidence: 0.91))
        #expect(byName["Nine Arch Bridge"]?.photoCount == 2)
        #expect(byName["Nine Arch Bridge"]?.tripName == "Hill Country")
        #expect(byName["Gal Vihara"]?.status == .confirmedByUser)
        #expect(byName["Sigiriya Rock Fortress"]?.status == .voiceOnly)
        #expect(byName["Temple of the Tooth"]?.status == .planned(trip: "Hill Country"), "on day 4 of the plan")
        #expect(byName["Lotus Tower"]?.status == .notVisited)
    }

    @Test func aSurePhotoIsLabelledAndLinkedToThePlan() async throws {
        let recognizer = FakeLandmarkRecognizer([result([("Nine Arch Bridge", 0.93), ("Other", 0.04)], scenes: ["bridge"])])
        let (form, store) = makeForm(recognizer)

        await form.addPhotos([photo()])
        #expect(form.landmark == "Nine Arch Bridge")
        #expect(form.landmarkConfidence == 0.93)
        #expect(form.linkedActivityID == bridge.id, "linked to the activity at that landmark")
        #expect(form.sceneTags == ["Bridge"])

        #expect(form.save())
        let saved = try #require(store.memories.first)
        #expect(saved.landmark == "Nine Arch Bridge")
        #expect(saved.landmarkConfidence == 0.93)
        #expect(saved.sceneTags == ["Bridge"])
        #expect(store.trip(trip.id)?.activities.first { $0.id == bridge.id }?.isDone == true, "marked as visited")
    }

    @Test func anUnsureGuessIsNeverSavedWithoutAsking() async throws {
        let recognizer = FakeLandmarkRecognizer([result([("Lotus Tower", 0.52), ("Nine Arch Bridge", 0.31), ("Other", 0.1)])])
        let (form, store) = makeForm(recognizer)

        await form.addPhotos([photo()])
        #expect(form.landmark == nil)
        #expect(form.needsLandmarkConfirmation)
        #expect(form.recognition?.suggestions.map(\.name) == ["Lotus Tower", "Nine Arch Bridge"])

        form.chooseLandmark("Nine Arch Bridge")
        #expect(form.landmarkChosenByUser)
        #expect(form.save())
        let saved = try #require(store.memories.first)
        #expect(saved.landmark == "Nine Arch Bridge")
        #expect(saved.landmarkConfidence == nil, "the user's choice, not the model's")
    }

    @Test func notALandmarkSavesNoLandmark() async throws {
        let recognizer = FakeLandmarkRecognizer([result([("Other", 0.88), ("Gal Vihara", 0.07)], scenes: ["food"])])
        let (form, store) = makeForm(recognizer)

        await form.addPhotos([photo()])
        #expect(form.needsLandmarkConfirmation)
        form.rejectLandmark()
        #expect(!form.needsLandmarkConfirmation)
        #expect(form.save())
        #expect(store.memories.first?.landmark == nil)
        #expect(store.memories.first?.sceneTags == ["Food"], "scene tags are still kept")
    }

    @Test func removingThePhotoRemovesItsLandmark() async {
        let recognizer = FakeLandmarkRecognizer([result([("Nine Arch Bridge", 0.95)])])
        let (form, _) = makeForm(recognizer)
        await form.addPhotos([photo()])
        #expect(form.landmark == "Nine Arch Bridge")

        form.removeNewPhoto(at: 0)
        #expect(form.landmark == nil)
        #expect(form.linkedActivityID == nil, "the activity it linked is unlinked too")
    }

    @Test func theClearestOfSeveralPhotosIsUsed() async {
        let recognizer = FakeLandmarkRecognizer([result([("Other", 0.97)]), result([("Nine Arch Bridge", 0.81)])])
        let (form, _) = makeForm(recognizer)
        await form.addPhotos([photo(.systemGreen), photo(.systemBlue)])
        #expect(recognizer.calls == 2)
        #expect(form.landmark == "Nine Arch Bridge", "a photo of the landmark wins over a photo of lunch")
    }

    @Test func aNoteNamingAnotherLandmarkAsksWhichIsRight() async {
        let recognizer = FakeLandmarkRecognizer([result([("Nine Arch Bridge", 0.9)])])
        let (form, _) = makeForm(recognizer)
        form.text = "Long climb up Sigiriya this morning"
        await form.addPhotos([photo()])
        #expect(form.conflictingLandmark?.name == "Sigiriya Rock Fortress")

        form.chooseLandmark("Sigiriya Rock Fortress")
        #expect(form.landmark == "Sigiriya Rock Fortress")
        #expect(form.conflictingLandmark == nil)
    }

    @Test func aSavedLandmarkIsKeptWhenAPhotoIsAdded() async throws {
        let store = TripStore(repository: InMemoryTripRepository(trips: [trip]), clock: FixedClock(now: now))
        var memory = Memory(tripID: trip.id, title: "Falls", date: now, day: 2, place: "Ella", transcript: "",
                            duration: 0, people: [])
        memory.landmark = "Gal Vihara"
        store.addMemory(memory)

        let recognizer = FakeLandmarkRecognizer([result([("Nine Arch Bridge", 0.9)])])
        let form = MemoryFormViewModel(memoryID: memory.id, store: store, clock: FixedClock(now: now), recognizer: recognizer)
        await form.addPhotos([photo()])
        #expect(form.landmark == "Gal Vihara", "the user can still change it by hand")
    }

    @Test func aModelProblemIsShownAndNothingIsGuessed() async {
        let recognizer = FakeLandmarkRecognizer()
        recognizer.error = LandmarkRecognitionError.modelUnavailable
        let (form, _) = makeForm(recognizer)
        await form.addPhotos([photo()])
        #expect(form.landmark == nil)
        #expect(form.recognitionProblem != nil)
        #expect(form.photoCount == 1, "the photo is still added")
    }

    // The real model

    private func modelLabels() throws -> [String] {
        let model = try LandmarkClassifier(configuration: .init()).model
        return model.modelDescription.classLabels as? [String] ?? []
    }

    @Test func theTrainedModelRecognisesPhotosItNeverSaw() async throws {
        // The app's own landmark photos were kept out of the training data (see MLTraining/collect_dataset.py)
        let recognizer = VisionLandmarkRecognizer()
        var correct: [String] = []
        var wrong: [String] = []
        for landmark in LandmarkCatalogue.all where landmark.photo != .colomboSkyline {
            let image = try #require(UIImage(named: landmark.photo.rawValue)?.jpegData(compressionQuality: 0.9))
            let recognition = try await recognizer.recognize(image)
            if recognition.top?.name == landmark.name {
                correct.append(landmark.name)
            } else {
                wrong.append("\(landmark.name) -> \(recognition.top?.name ?? "nothing")")
            }
            #expect((0.3...0.95).contains(recognition.threshold), "threshold read from the model")
        }
        #expect(correct.count >= 10, "only \(correct.count) right. Wrong: \(wrong)")
    }
}
