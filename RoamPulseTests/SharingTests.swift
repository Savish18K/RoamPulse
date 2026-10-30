import Foundation
import Testing
@testable import RoamPulse

@MainActor
struct SharingTests {
    let owner = "uid-savishka"
    let friend = "uid-samee"
    let now = Calendar.trip.date(2026, 12, 13, 16, 40)
    // Same ids for the whole test
    let hill: Trip

    init() {
        hill = Self.makeTrip(owner: "uid-savishka", now: Calendar.trip.date(2026, 12, 13, 16, 40))
    }

    private func trip() -> Trip { hill }

    private static func makeTrip(owner: String, now: Date) -> Trip {
        var trip = Trip(name: "Hill Country Explorer", destination: "Kandy to Ella", startDate: now,
                        endDate: Calendar.trip.date(2026, 12, 16), budget: 120_000,
                        members: [Member(name: "Savishka", colorHex: 1, isMe: true, userUID: owner),
                                  Member(name: "Samee", colorHex: 2),
                                  Member(name: "Suu", colorHex: 3)],
                        cover: .hillTrain)
        trip.ownerUID = owner
        trip.memberUIDs = [owner]
        return trip
    }

    @Test func codesAreEightUnambiguousCharacters() {
        let codes = (0..<200).map { _ in InviteCode.generate() }
        #expect(codes.allSatisfy { $0.count == InviteCode.length })
        #expect(codes.allSatisfy { $0.allSatisfy(InviteCode.alphabet.contains) })
        #expect(codes.allSatisfy { !$0.contains("O") && !$0.contains("0") && !$0.contains("I") && !$0.contains("1") })
        #expect(Set(codes).count == codes.count, "no repeats in 200 codes")
    }

    @Test func typedCodesAreCleanedUp() {
        #expect(InviteCode.normalized(" k7qm-2xha ") == "K7QM2XHA")
        #expect(InviteCode.normalized("K7QM 2XHA") == "K7QM2XHA")
        #expect(InviteCode.normalized("K7QM") == nil, "too short")
        #expect(InviteCode.normalized("O0IL1234") == nil, "letters that are never used")
        #expect(InviteCode.formatted("K7QM2XHA") == "K7QM-2XHA")
    }

    @Test func anInviteListsWhoIsAlreadyLinkedAndExpiresInAWeek() {
        let invite = InviteCode.makeInvite(for: trip(), code: "K7QM2XHA", ownerName: "Savishka Kuruppu",
                                           accountID: owner, now: now)
        #expect(invite.availableMembers.map(\.name) == ["Samee", "Suu"], "Savishka is already linked")
        #expect(invite.expiresAt == now.addingTimeInterval(7 * 24 * 60 * 60))
        #expect(!invite.isExpired(at: now))
        #expect(invite.isExpired(at: invite.expiresAt))
        #expect(InviteCode.shareMessage(for: invite).contains("K7QM-2XHA"))
        #expect(InviteRecord(invite).invite(code: invite.code) == invite, "survives the trip through Firestore")
    }

    @Test func someoneNotOnTheListIsAddedAsANewLinkedMember() {
        let (_, record) = InviteCode.newMember(name: "Suresha", initials: "SR", accountID: friend, existingCount: 3)
        #expect(record.position == 3, "added at the end of the list")
        #expect(record.userUID == friend)
    }

    @Test func eachPhoneWorksOutWhoIsMe() {
        var shared = trip()
        shared.memberUIDs = [owner, friend]
        shared.members[1].userUID = friend // Samee joined as herself

        let items = TripRecords.items(for: shared, accountID: owner)
        var cloud = RemoteTripMirror()
        cloud.receiveHeader(TripRecords.header(for: shared, accountID: owner, updatedAt: now), hasPendingWrites: false)
        for collection in SyncCollection.allCases {
            var records: [String: ItemRecord] = [:]
            for (key, record) in items where key.collection == collection { records[key.id] = record }
            cloud.receive(records, in: collection, hasPendingWrites: false)
        }

        let onSameesPhone = cloud.trip(id: shared.id, accountID: friend)
        #expect(onSameesPhone?.members.filter(\.isMe).map(\.name) == ["Samee"])
        #expect(onSameesPhone?.ownerUID == owner, "the owner doesn't change when someone else's phone downloads it")
        #expect(onSameesPhone?.memberUIDs == [owner, friend])
    }

    @Test func editsNeverRewriteWhoIsOnTheTrip() {
        // Samee's phone doesn't know Suu joined yet
        var old = trip()
        old.memberUIDs = [owner, friend]
        var renamed = old
        renamed.name = "Ella Weekend"
        let writes = TripChangeSet.writes(from: old, to: renamed, accountID: friend, now: now)

        // Updates only write content fields, Suu's uid isn't touched
        guard case .updateTrip = writes.first else {
            Issue.record("Expected a content-only update")
            return
        }
        #expect(!TripRecord.contentFields.contains("memberUIDs"))
        #expect(!TripRecord.contentFields.contains("ownerUID"))

        // Member changes alone upload nothing
        var joined = old
        joined.memberUIDs.append("uid-suu")
        #expect(TripChangeSet.writes(from: old, to: joined, accountID: friend, now: now).isEmpty)
    }

    private func makeStore(account: String, trips: [Trip] = []) -> (TripStore, RecordingSyncService) {
        let store = TripStore(repository: InMemoryTripRepository(trips: trips), clock: FixedClock(now: now))
        store.open(repository: InMemoryTripRepository(trips: trips),
                   user: AppUser(uid: account, email: "\(account)@mail.com", displayName: "Savishka Kuruppu"))
        let sync = RecordingSyncService()
        store.sync = sync
        return (store, sync)
    }

    @Test func aNewTripBelongsToWhoeverMadeIt() {
        let (store, _) = makeStore(account: owner)
        let new = Trip(name: "Galle", destination: "Galle", startDate: now, endDate: now, budget: 0,
                       members: [Member(name: "Savishka", colorHex: 0, isMe: true)], cover: .galleFort)
        store.addTrip(new)

        let saved = store.trip(new.id)
        #expect(saved?.ownerUID == owner)
        #expect(saved?.memberUIDs == [owner])
        #expect(saved?.members.first?.userUID == owner, "me is linked to my account")
        #expect(saved.map(store.isOwner) == true)
    }

    @Test func deletingSomeoneElsesTripLeavesItInsteadOfDeletingIt() {
        var shared = trip()
        shared.memberUIDs = [owner, friend]
        let (store, sync) = makeStore(account: friend, trips: [shared])
        #expect(!store.isOwner(of: shared))

        store.deleteTrip(shared.id)
        #expect(store.trips.isEmpty, "gone from this phone")
        #expect(sync.leftTrips == [shared.id])
        #expect(sync.changes.isEmpty, "no tombstone: it stays for the rest of the group")
    }

    @Test func theOwnerDeletesTheTripForEveryone() {
        let (store, sync) = makeStore(account: owner, trips: [trip()])
        store.deleteTrip(trip().id)
        #expect(sync.changes.count == 1)
        #expect(sync.leftTrips.isEmpty)
    }

    @Test func sharingMakesACodeAndMessage() async {
        let (store, sync) = makeStore(account: owner, trips: [trip()])
        sync.start(accountID: owner, store: store)
        let share = ShareTripViewModel(tripID: trip().id, store: store, sync: sync)
        await share.createInvite()

        #expect(share.formattedCode == "K7QM-2XHA")
        #expect(share.shareMessage.contains("Hill Country Explorer"))
        #expect(share.joinedMembers.map(\.name) == ["Savishka"])
    }

    @Test func sharingOfflineExplainsWhy() async {
        let (store, sync) = makeStore(account: owner, trips: [trip()])
        sync.sharingError = .offline
        let share = ShareTripViewModel(tripID: trip().id, store: store, sync: sync)
        await share.createInvite()
        #expect(share.state == .failed(SharingError.offline.errorDescription ?? ""))
        #expect(share.failedOffline)
    }

    @Test func refusedByTheCloudSaysSoInsteadOfBlamingTheConnection() async {
        let (store, sync) = makeStore(account: owner, trips: [trip()])
        sync.sharingError = .refused
        let share = ShareTripViewModel(tripID: trip().id, store: store, sync: sync)
        await share.createInvite()
        #expect(share.state == .failed(SharingError.refused.errorDescription ?? ""))
        #expect(!share.failedOffline, "not shown as a Wi-Fi problem")
    }

    @Test func joiningPicksTheMemberWithYourNameAndJoinsAsThem() async {
        let (store, sync) = makeStore(account: friend)
        sync.invites["K7QM2XHA"] = InviteCode.makeInvite(for: trip(), code: "K7QM2XHA", ownerName: "Savishka",
                                                         accountID: owner, now: now)
        store.updateAccount(AppUser(uid: friend, email: "samee@mail.com", displayName: "Samee"))
        let join = JoinTripViewModel(store: store, sync: sync)

        join.code = "abc"
        await join.findTrip()
        #expect(join.errorMessage != nil, "not a code")

        join.code = "k7qm-2xha"
        await join.findTrip()
        let samee = join.invite?.members.first { $0.name == "Samee" }
        #expect(join.selectedMemberID == samee?.id)

        await join.join()
        #expect(join.step == .joined(tripName: "Hill Country Explorer"))
        #expect(sync.joined.first?.memberID == samee?.id)
    }

    @Test func anUnknownCodeShowsAMessage() async {
        let (store, sync) = makeStore(account: friend)
        let join = JoinTripViewModel(store: store, sync: sync)
        join.code = "K7QM2XHA"
        await join.findTrip()
        #expect(join.errorMessage == SharingError.inviteNotFound.errorDescription)
        #expect(join.step == .enterCode)
    }

    @Test func aQuickAnswerIsReturned() async throws {
        let value = try await withTimeout(seconds: 2) { 42 }
        #expect(value == 42)
    }

    @Test func aWriteStuckOfflineGivesUp() async {
        await #expect(throws: SharingError.offline) {
            try await withTimeout(seconds: 0.1) {
                try await Task.sleep(for: .seconds(5))
                return 1
            }
        }
    }
}
