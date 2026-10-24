import CoreData
import Foundation
import Testing
@testable import RoamPulse

// In-memory store so the real database isn't touched
@MainActor
struct CoreDataRepositoryTests {
    let persistence = PersistenceController(inMemory: true)
    var context: NSManagedObjectContext { persistence.container.viewContext }
    var repository: CoreDataTripRepository { CoreDataTripRepository(context: context) }

    let me = Member(name: "Savishka", initials: "SK", colorHex: 0xD9738F, isMe: true)
    let samee = Member(name: "Samee", initials: "SM", colorHex: 0x5B8FD6)

    // Uses every kind of child row
    private func sampleTrip() -> Trip {
        let start = Calendar.trip.date(2026, 12, 12)
        var trip = Trip(name: "Hill Country Explorer", destination: "Kandy to Ella",
                        startDate: start, endDate: Calendar.trip.date(2026, 12, 15),
                        budget: 120_000, members: [me, samee], cover: .hillTrain, remindersOn: false)
        trip.activities = [
            Activity(day: 1, title: "Temple of the Tooth", minutes: 690, place: "Kandy", effort: .low, isDone: true),
            Activity(day: 3, title: "Little Adam's Peak", minutes: 360, place: "Ella", effort: .high, isOutdoor: true),
        ]
        trip.packing = [
            PackingItem(name: "Passport", category: "Documents", isPacked: true),
            PackingItem(name: "Poncho", category: "Rain Gear"),
        ]
        trip.expenses = [
            Expense(title: "Train tickets", amount: 6_200, category: .transport, paidBy: me,
                    shares: ExpenseCalculator.equalShares(of: 6_200, between: [me, samee]), date: start),
            Expense(title: "Dinner", amount: 3_000.5, category: .food, paidBy: samee, splitMethod: .custom,
                    shares: [ExpenseShare(member: me, amount: 2_000.5), ExpenseShare(member: samee, amount: 1_000)],
                    date: start),
        ]
        trip.payments = [Payment(from: samee, to: me, amount: 1_000, date: start)]
        return trip
    }

    private func count(_ entityName: String) throws -> Int {
        try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entityName))
    }

    @Test func aTripComesBackExactlyAsItWasSaved() throws {
        let trip = sampleTrip()
        try repository.save(trip)

        // New repository on the same store, like reopening the app
        let loaded = try CoreDataTripRepository(context: context).loadTrips()
        #expect(loaded == [trip])
    }

    @Test func savingAgainUpdatesRowsInsteadOfAddingNewOnes() throws {
        var trip = sampleTrip()
        try repository.save(trip)

        trip.name = "Hill Country Weekend"
        trip.activities.removeFirst()
        trip.packing.append(PackingItem(name: "Camera rain cover", category: "Rain Gear"))
        trip.expenses[1].shares = [ExpenseShare(member: samee, amount: 3_000.5)]
        try repository.save(trip)

        #expect(try repository.loadTrips() == [trip])
        #expect(try count("TripEntity") == 1)
        #expect(try count("ActivityEntity") == 1)
        #expect(try count("PackingItemEntity") == 3)
        #expect(try count("ExpenseShareEntity") == 3) // 2 for the train, 1 for the dinner
    }

    @Test func deletingATripDeletesEverythingInIt() throws {
        let trip = sampleTrip()
        try repository.save(trip)
        let memory = Memory(tripID: trip.id, title: "Blue train", date: trip.startDate, day: 2, place: "Ella",
                            transcript: "", duration: 0, people: [samee], photos: [.sample(.nineArchBridge)])
        try repository.save(memory)

        try repository.deleteTrip(id: trip.id)

        for entity in ["TripEntity", "MemberEntity", "ActivityEntity", "PackingItemEntity", "ExpenseEntity",
                       "ExpenseShareEntity", "PaymentEntity", "MemoryEntity", "PhotoEntity"] {
            #expect(try count(entity) == 0, "\(entity) rows were left behind")
        }
    }

    @Test func aMemoryKeepsItsTagsPeopleAndPhotos() throws {
        let trip = sampleTrip()
        try repository.save(trip)
        let memory = Memory(tripID: trip.id, title: "Blue train at Nine Arch Bridge", date: trip.startDate, day: 2,
                            place: "Ella", transcript: "It crossed right on time.", duration: 80, people: [samee],
                            mood: .positive, sentiment: 0.71, placeTags: ["Ella", "Demodara"],
                            landmark: "Nine Arch Bridge", landmarkConfidence: 0.94, sceneTags: ["Bridge", "Forest"],
                            photos: [.sample(.nineArchBridge), .sample(.blueTrainBridge)], isVisited: true)
        try repository.save(memory)

        #expect(try repository.loadMemories() == [memory])
    }

    @Test func aMemoryNeedsItsTrip() {
        let orphan = Memory(tripID: UUID(), title: "Lost", date: .now, day: 1, place: "Ella",
                            transcript: "", duration: 0, people: [])
        #expect(throws: RepositoryError.tripNotFound) {
            try repository.save(orphan)
        }
    }

    @Test func deleteEverythingEmptiesTheDatabase() throws {
        try repository.save(sampleTrip())
        try repository.deleteEverything()
        #expect(try repository.loadTrips().isEmpty)
        #expect(try count("MemberEntity") == 0)
    }
}
