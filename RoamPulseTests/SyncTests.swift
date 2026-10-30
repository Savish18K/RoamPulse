import Foundation
import Testing
@testable import RoamPulse

// None of this needs Firebase
@MainActor
struct SyncTests {
    let account = "uid-savishka"
    let now = Calendar.trip.date(2026, 12, 13, 16, 40)
    let me = Member(name: "Savishka", initials: "SK", colorHex: 0xD9738F, isMe: true, userUID: "uid-savishka")
    let samee = Member(name: "Samee", initials: "SM", colorHex: 0x5B8FD6)

    private func sampleTrip() -> Trip {
        let start = Calendar.trip.date(2026, 12, 12)
        var trip = Trip(name: "Hill Country Explorer", destination: "Kandy to Ella", startDate: start,
                        endDate: Calendar.trip.date(2026, 12, 15), budget: 120_000, members: [me, samee],
                        cover: .hillTrain, remindersOn: false)
        trip.ownerUID = account
        trip.memberUIDs = [account]
        trip.latitude = 6.8667
        trip.longitude = 81.0466
        trip.activities = [
            Activity(day: 1, title: "Temple of the Tooth", minutes: 690, place: "Kandy", effort: .low, isDone: true),
            Activity(day: 3, title: "Little Adam's Peak", minutes: 360, place: "Ella", effort: .high, isOutdoor: true),
        ]
        trip.packing = [
            PackingItem(name: "Passport", category: "Documents", isPacked: true),
            PackingItem(name: "Poncho", category: "Rain Gear"),
            PackingItem(name: "Camera", category: "Electronics"),
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

    // What the 6 listeners would send
    private func mirror(of trip: Trip, pending: Bool = false) -> RemoteTripMirror {
        var mirror = RemoteTripMirror()
        mirror.receiveHeader(TripRecords.header(for: trip, accountID: account, updatedAt: now), hasPendingWrites: pending)
        let items = TripRecords.items(for: trip, accountID: account)
        for collection in SyncCollection.allCases {
            var records: [String: ItemRecord] = [:]
            for (key, record) in items where key.collection == collection {
                records[key.id] = record
            }
            mirror.receive(records, in: collection, hasPendingWrites: false)
        }
        return mirror
    }

    @Test func aTripSurvivesTheRoundTripThroughFirestoreRecords() {
        let trip = sampleTrip()
        #expect(mirror(of: trip).trip(id: trip.id, accountID: account) == trip)
    }

    @Test func moneyIsStoredAsWholeCents() {
        let items = TripRecords.items(for: sampleTrip(), accountID: account)
        let dinner = items.values.compactMap(\.expense).first { $0.title == "Dinner" }
        #expect(dinner?.amountCents == 300_050)
        #expect(dinner?.shares.map(\.amountCents) == [200_050, 100_000])
        #expect(TripRecords.amount(cents: 300_050) == 3_000.5)
    }

    @Test func aTripMadeBeforeOwnersExistedBelongsToTheSignedInAccount() {
        var trip = sampleTrip()
        trip.ownerUID = nil
        trip.memberUIDs = []
        let header = TripRecords.header(for: trip, accountID: account, updatedAt: now)
        #expect(header.ownerUID == account)
        #expect(header.memberUIDs == [account])
    }

    @Test func listOrderIsKeptEvenThoughFirestoreSortsById() {
        var trip = sampleTrip()
        trip.packing.reverse()
        #expect(mirror(of: trip).trip(id: trip.id, accountID: account)?.packing.map(\.name) == ["Camera", "Poncho", "Passport"])
    }

    @Test func anExpenseWhosePayerIsMissingIsSkipped() {
        var trip = sampleTrip()
        var cloud = mirror(of: trip)
        var members: [String: ItemRecord] = [:]
        for (key, record) in TripRecords.items(for: trip, accountID: account)
            where key.collection == .members && record.member?.name == "Savishka" {
            members[key.id] = record
        }
        cloud.receive(members, in: .members, hasPendingWrites: false) // Samee's document is gone

        let rebuilt = cloud.trip(id: trip.id, accountID: account)
        trip.members = [me]
        #expect(rebuilt?.members == trip.members)
        #expect(rebuilt?.expenses.map(\.title) == ["Train tickets"], "Dinner was paid by Samee")
        #expect(rebuilt?.expenses.first?.shares.count == 1)
        #expect(rebuilt?.payments.isEmpty == true)
    }

    @Test func aNewTripCreatesItsDocumentFirstAndThenEveryItem() {
        let trip = sampleTrip()
        let writes = TripChangeSet.writes(from: nil, to: trip, accountID: account, now: now)
        #expect(writes.first == .createTrip(trip.id, TripRecords.header(for: trip, accountID: account, updatedAt: now)))
        // 2 members + 2 activities + 3 packing + 2 expenses + 1 payment
        #expect(writes.count == 1 + 10)
    }

    @Test func tickingOnePackingItemIsOneWrite() {
        let old = sampleTrip()
        var new = old
        new.packing[1].isPacked = true
        let writes = TripChangeSet.writes(from: old, to: new, accountID: account, now: now)
        #expect(writes.count == 1)
        guard case .setItem(_, let key, .packing(let record)) = writes.first else {
            Issue.record("Expected one packing write")
            return
        }
        #expect(key == ItemKey(collection: .packing, id: old.packing[1].id.uuidString))
        #expect(record.isPacked)
    }

    @Test func renamingATripOnlyUpdatesItsDocument() {
        let old = sampleTrip()
        var new = old
        new.name = "Ella Weekend"
        let writes = TripChangeSet.writes(from: old, to: new, accountID: account, now: now)
        #expect(writes == [.updateTrip(old.id, TripRecords.header(for: new, accountID: account, updatedAt: now))])
    }

    @Test func removingAnExpenseDeletesItsDocument() {
        let old = sampleTrip()
        var new = old
        new.expenses.removeLast()
        let writes = TripChangeSet.writes(from: old, to: new, accountID: account, now: now)
        #expect(writes == [.deleteItem(tripID: old.id, ItemKey(collection: .expenses, id: old.expenses[1].id.uuidString))])
    }

    @Test func changingOnlyTheCoverPhotoUploadsNothing() {
        let old = sampleTrip()
        var new = old
        new.coverImageID = UUID()
        #expect(TripChangeSet.writes(from: old, to: new, accountID: account, now: now).isEmpty)
    }

    @Test func deletingATripLeavesAnEmptyTombstoneAndRemovesItsItems() {
        let trip = sampleTrip()
        let writes = TripChangeSet.writes(from: trip, to: nil, accountID: account, now: now)
        guard case .updateTrip(let id, let record) = writes.first else {
            Issue.record("Expected the trip's document first")
            return
        }
        #expect(id == trip.id)
        #expect(record.isDeleted)
        #expect(record.name.isEmpty && record.destination.isEmpty && record.budget == 0, "no personal data is left")
        #expect(record.latitude == nil)
        #expect(writes.dropFirst().allSatisfy { if case .deleteItem = $0 { true } else { false } })
        #expect(writes.count == 1 + 10)
    }

    @Test func aTripIsOnlyBuiltOnceEveryPartHasArrived() {
        let trip = sampleTrip()
        var cloud = RemoteTripMirror()
        cloud.receiveHeader(TripRecords.header(for: trip, accountID: account, updatedAt: now), hasPendingWrites: false)
        cloud.receive([:], in: .members, hasPendingWrites: false)
        #expect(cloud.trip(id: trip.id, accountID: account) == nil, "the other lists haven't arrived yet")

        let complete = mirror(of: trip)
        #expect(complete.hasEveryPart)
        #expect(complete.trip(id: trip.id, accountID: account) != nil)
    }

    @Test func unconfirmedWritesFromThisPhoneHoldTheCloudCopyBack() {
        var cloud = mirror(of: sampleTrip(), pending: true)
        #expect(cloud.hasPendingWrites)

        let trip = sampleTrip()
        cloud.receiveHeader(TripRecords.header(for: trip, accountID: account, updatedAt: now), hasPendingWrites: false)
        #expect(!cloud.hasPendingWrites, "the server confirmed the write")
    }

    @Test func aDeletedTripIsNeverRebuilt() {
        let trip = sampleTrip()
        var cloud = mirror(of: trip)
        cloud.receiveHeader(TripRecord.tombstone(owner: account, members: [account], at: now), hasPendingWrites: false)
        #expect(cloud.trip(id: trip.id, accountID: account) == nil)
    }

    private func makeStore(_ trips: [Trip] = []) -> (TripStore, RecordingSyncService, InMemoryTripRepository) {
        let repository = InMemoryTripRepository(trips: trips)
        let store = TripStore(repository: repository, clock: FixedClock(now: now))
        let sync = RecordingSyncService()
        store.sync = sync
        return (store, sync, repository)
    }

    @Test func everySavedChangeIsPassedToSync() {
        let (store, sync, _) = makeStore()
        let trip = sampleTrip()

        store.addTrip(trip)
        store.updateTrip(trip.id) { $0.budget = 150_000 }
        store.updateTrip(trip.id) { $0.budget = 150_000 } // no change
        store.deleteTrip(trip.id)

        #expect(sync.changes.count == 3)
        #expect(sync.changes[0].old == nil && sync.changes[0].new == trip)
        #expect(sync.changes[1].old?.budget == 120_000 && sync.changes[1].new?.budget == 150_000)
        #expect(sync.changes[2].new == nil && sync.changes[2].old?.id == trip.id)
    }

    @Test func aChangeThatFailedToSaveIsNotUploaded() {
        let trip = sampleTrip()
        let (store, sync, repository) = makeStore([trip])
        repository.failSaves = true
        store.updateTrip(trip.id) { $0.name = "Never saved" }
        #expect(sync.changes.isEmpty)
        #expect(store.errorMessage != nil)
    }

    @Test func changesFromTheCloudAreSavedButNotUploadedAgain() throws {
        let trip = sampleTrip()
        let (store, sync, repository) = makeStore([trip])
        var remote = trip
        remote.name = "Renamed on the iPad"

        store.applyRemote(remote)
        #expect(store.trip(trip.id)?.name == "Renamed on the iPad")
        #expect(try repository.loadTrips().first?.name == "Renamed on the iPad")

        var newTrip = sampleTrip()
        newTrip.id = UUID()
        store.applyRemote(newTrip)
        #expect(store.trips.count == 2)
        #expect(sync.changes.isEmpty)
    }

    @Test func theCloudCopyKeepsThisPhonesCoverPhoto() {
        var trip = sampleTrip()
        let coverID = UUID()
        trip.coverImageID = coverID
        let (store, _, repository) = makeStore([trip])

        var remote = trip
        remote.coverImageID = nil // covers aren't synced
        repository.failSaves = true // the copies are identical, so nothing should be saved
        store.applyRemote(remote)

        #expect(store.trip(trip.id)?.coverImageID == coverID)
        #expect(store.errorMessage == nil)
    }

    @Test func aTripDeletedElsewhereIsRemovedWithItsMemoriesAndNotUploaded() {
        let trip = sampleTrip()
        let (store, sync, _) = makeStore([trip])
        store.addMemory(Memory(tripID: trip.id, title: "Blue train", date: now, day: 2, place: "Ella",
                               transcript: "", duration: 30, people: []))

        store.applyRemoteDeletion(trip.id)
        #expect(store.trips.isEmpty)
        #expect(store.memories.isEmpty)
        #expect(sync.changes.isEmpty)
    }

    @Test func deleteAllDataAlsoDeletesTheTripsFromTheCloud() {
        var second = sampleTrip()
        second.id = UUID()
        let (store, sync, _) = makeStore([sampleTrip(), second])
        store.deleteAllData()
        #expect(sync.changes.count == 2)
        #expect(sync.changes.allSatisfy { $0.new == nil })
    }

    @Test func editingATripWithoutCoordinatesStillUploads() throws {
        var upcoming = sampleTrip()
        upcoming.latitude = nil
        upcoming.longitude = nil
        let record = TripRecords.header(for: upcoming, accountID: account, updatedAt: now)

        // Every merged field has to be in the data, or Firestore throws and the app crashes
        let data = try FirestoreSyncService.mergeData(for: record)
        #expect(Set(TripRecord.contentFields).isSubset(of: Set(data.keys)))
        #expect(data["budget"] as? Double == upcoming.budget)
    }
}
