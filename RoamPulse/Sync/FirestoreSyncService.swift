import FirebaseFirestore
import Foundation
import Observation

// Syncs trips between Core Data and Firestore. Local changes go up as a batch, listeners bring changes down
// If two phones edit the same item the last write wins
@MainActor
@Observable
final class FirestoreSyncService: SyncService {
    private(set) var status: SyncStatus = .off

    // Firestore allows 500 writes per batch, stay under it
    private static let batchLimit = 450

    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private weak var store: TripStore?
    @ObservationIgnored private var accountID: String?
    @ObservationIgnored private var tripsListener: ListenerRegistration?
    @ObservationIgnored private var listListeners: [UUID: [ListenerRegistration]] = [:]
    @ObservationIgnored private var mirrors: [UUID: RemoteTripMirror] = [:]
    @ObservationIgnored private var didUploadMissingTrips = false
    @ObservationIgnored private var tripsAreFromCache = true
    @ObservationIgnored private var errorMessage: String?

    init(clock: Clock) {
        self.clock = clock
    }

    private var db: Firestore { Firestore.firestore() }

    private func tripDocument(_ id: UUID) -> DocumentReference {
        db.collection("trips").document(id.uuidString)
    }

    func start(accountID: String, store: TripStore) {
        stop()
        self.accountID = accountID
        self.store = store
        status = .connecting

        // includeMetadataChanges so we also hear about confirmed writes and going offline
        tripsListener = db.collection("trips")
            .whereField("memberUIDs", arrayContains: accountID)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                MainActor.assumeIsolated {
                    self?.tripsChanged(snapshot, error: error)
                }
            }
    }

    func stop() {
        tripsListener?.remove()
        tripsListener = nil
        for listeners in listListeners.values {
            listeners.forEach { $0.remove() }
        }
        listListeners = [:]
        mirrors = [:]
        accountID = nil
        store = nil
        didUploadMissingTrips = false
        tripsAreFromCache = true
        errorMessage = nil
        status = .off
    }

    func tripDidChange(from old: Trip?, to new: Trip?) {
        guard let accountID else { return }
        let writes = TripChangeSet.writes(from: old, to: new, accountID: accountID, now: clock.now)
        upload(writes)
    }

    private func upload(_ writes: [SyncWrite]) {
        guard !writes.isEmpty else { return }
        // Trip doc goes first because the rules need it to exist
        for start in stride(from: 0, to: writes.count, by: Self.batchLimit) {
            let batch = db.batch()
            do {
                for write in writes[start..<min(start + Self.batchLimit, writes.count)] {
                    try add(write, to: batch)
                }
            } catch {
                report(error)
                return
            }
            // Only runs once back online, so don't wait for it
            batch.commit { [weak self] error in
                guard let error else { return }
                MainActor.assumeIsolated {
                    self?.report(error)
                }
            }
        }
    }

    private func add(_ write: SyncWrite, to batch: WriteBatch) throws {
        switch write {
        case .createTrip(let id, let record):
            try batch.setData(from: record, forDocument: tripDocument(id))
        case .updateTrip(let id, let record):
            try batch.setData(from: record, forDocument: tripDocument(id), mergeFields: TripRecord.contentFields)
        case .setItem(let tripID, let key, let item):
            let document = tripDocument(tripID).collection(key.collection.rawValue).document(key.id)
            switch item {
            case .member(let record): try batch.setData(from: record, forDocument: document)
            case .activity(let record): try batch.setData(from: record, forDocument: document)
            case .packing(let record): try batch.setData(from: record, forDocument: document)
            case .expense(let record): try batch.setData(from: record, forDocument: document)
            case .payment(let record): try batch.setData(from: record, forDocument: document)
            }
        case .deleteItem(let tripID, let key):
            batch.deleteDocument(tripDocument(tripID).collection(key.collection.rawValue).document(key.id))
        }
    }

    private var invites: CollectionReference { db.collection("invites") }

    func createInvite(for trip: Trip, ownerName: String) async throws -> TripInvite {
        guard let accountID else { throw SharingError.notSignedIn }
        let invite = InviteCode.makeInvite(for: trip, code: InviteCode.generate(), ownerName: ownerName,
                                           accountID: accountID, now: clock.now)
        let data = try Firestore.Encoder().encode(InviteRecord(invite))
        let document = invites.document(invite.code)
        try await withTimeout {
            try await document.setData(data)
        }
        return invite
    }

    func findInvite(code: String) async throws -> TripInvite {
        guard accountID != nil else { throw SharingError.notSignedIn }
        guard let code = InviteCode.normalized(code) else { throw SharingError.inviteNotFound }
        let document = invites.document(code)
        // Get it from the server, the cache might be old
        let snapshot: DocumentSnapshot
        do {
            snapshot = try await withTimeout { try await document.getDocument(source: .server) }
        } catch let error as SharingError {
            throw error
        } catch {
            throw SharingError.offline
        }
        guard snapshot.exists, let invite = try? snapshot.data(as: InviteRecord.self).invite(code: code) else {
            throw SharingError.inviteNotFound
        }
        guard !invite.isExpired(at: clock.now) else { throw SharingError.inviteExpired }
        guard store?.trip(invite.tripID) == nil else { throw SharingError.alreadyMember }
        return invite
    }

    func joinTrip(_ invite: TripInvite, as memberID: String?, name: String, initials: String) async throws {
        guard let accountID else { throw SharingError.notSignedIn }
        let trip = tripDocument(invite.tripID)

        // 1. Add this account to the trip (rules check the invite)
        try await withTimeout {
            try await trip.updateData([
                "memberUIDs": FieldValue.arrayUnion([accountID]),
                "joinCode": invite.code,
            ])
        }

        // 2. Link the account to a member so the app knows who "me" is
        let members = trip.collection(SyncCollection.members.rawValue)
        if let memberID {
            try await withTimeout {
                try await members.document(memberID).updateData(["userUID": accountID])
            }
        } else {
            let newMember = InviteCode.newMember(name: name, initials: initials, accountID: accountID,
                                                 existingCount: invite.members.count)
            let data = try Firestore.Encoder().encode(newMember.record)
            try await withTimeout {
                try await members.document(newMember.id.uuidString).setData(data)
            }
        }
        // The trips listener picks it up from here
    }

    func leaveTrip(_ trip: Trip) {
        guard let accountID else { return }
        let document = tripDocument(trip.id)
        // Unlink "me" first, then leave. Writes are sent in order so this works offline
        if let me = trip.members.first(where: { $0.userUID == accountID }) {
            document.collection(SyncCollection.members.rawValue).document(me.id.uuidString)
                .updateData(["userUID": FieldValue.delete()]) { [weak self] error in
                    guard let error else { return }
                    MainActor.assumeIsolated { self?.report(error) }
                }
        }
        document.updateData([
            "memberUIDs": FieldValue.arrayRemove([accountID]),
            "updatedAt": clock.now,
        ]) { [weak self] error in
            guard let error else { return }
            MainActor.assumeIsolated { self?.report(error) }
        }
        stopListening(to: trip.id)
    }

    func deleteCloudData(for trips: [Trip]) async throws {
        guard let accountID else { throw SharingError.notSignedIn }

        // Own trips get a tombstone, shared ones we just leave
        var writes: [SyncWrite] = []
        for trip in trips {
            if trip.ownerUID == nil || trip.ownerUID == accountID {
                writes += TripChangeSet.writes(from: trip, to: nil, accountID: accountID, now: clock.now)
            } else {
                leaveTrip(trip)
            }
        }
        for start in stride(from: 0, to: writes.count, by: Self.batchLimit) {
            let batch = db.batch()
            for write in writes[start..<min(start + Self.batchLimit, writes.count)] {
                try add(write, to: batch)
            }
            // Wait for the server here, after the account is deleted these would be rejected
            try await withTimeout(seconds: 20) {
                try await batch.commit()
            }
        }

        let query = invites.whereField("createdBy", isEqualTo: accountID)
        let myInvites = try await withTimeout {
            try await query.getDocuments(source: .server)
        }
        for invite in myInvites.documents {
            try await withTimeout {
                try await invite.reference.delete()
            }
        }
    }

    private func tripsChanged(_ snapshot: QuerySnapshot?, error: Error?) {
        guard let snapshot else {
            report(error)
            return
        }
        tripsAreFromCache = snapshot.metadata.isFromCache

        // Trip left the query, stop listening but keep the local copy
        for change in snapshot.documentChanges where change.type == .removed {
            if let id = UUID(uuidString: change.document.documentID) {
                stopListening(to: id)
            }
        }

        for document in snapshot.documents {
            guard let id = UUID(uuidString: document.documentID),
                  let record = try? document.data(as: TripRecord.self) else { continue }

            if record.isDeleted {
                stopListening(to: id)
                store?.applyRemoteDeletion(id)
                continue
            }
            mirrors[id, default: RemoteTripMirror()]
                .receiveHeader(record, hasPendingWrites: document.metadata.hasPendingWrites)
            listenToLists(of: id)
            applyIfReady(id)
        }

        // First server answer: upload any trips the cloud is missing
        if !didUploadMissingTrips && !snapshot.metadata.isFromCache {
            didUploadMissingTrips = true
            let cloudIDs = Set(snapshot.documents.compactMap { UUID(uuidString: $0.documentID) })
            for trip in store?.trips ?? [] where !cloudIDs.contains(trip.id) {
                tripDidChange(from: nil, to: trip)
            }
        }
        updateStatus()
    }

    private func listenToLists(of tripID: UUID) {
        guard listListeners[tripID] == nil else { return }
        let trip = tripDocument(tripID)
        listListeners[tripID] = SyncCollection.allCases.map { collection in
            trip.collection(collection.rawValue)
                .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                    MainActor.assumeIsolated {
                        self?.listChanged(collection, of: tripID, snapshot, error: error)
                    }
                }
        }
    }

    private func listChanged(_ collection: SyncCollection, of tripID: UUID, _ snapshot: QuerySnapshot?, error: Error?) {
        guard let snapshot else {
            report(error)
            return
        }
        var records: [String: ItemRecord] = [:]
        for document in snapshot.documents {
            // Skip documents we can't read
            if let record = Self.record(in: collection, from: document) {
                records[document.documentID] = record
            }
        }
        mirrors[tripID, default: RemoteTripMirror()]
            .receive(records, in: collection, hasPendingWrites: snapshot.metadata.hasPendingWrites)
        applyIfReady(tripID)
        updateStatus()
    }

    private static func record(in collection: SyncCollection, from document: QueryDocumentSnapshot) -> ItemRecord? {
        switch collection {
        case .members: (try? document.data(as: MemberRecord.self)).map(ItemRecord.member)
        case .activities: (try? document.data(as: ActivityRecord.self)).map(ItemRecord.activity)
        case .packing: (try? document.data(as: PackingRecord.self)).map(ItemRecord.packing)
        case .expenses: (try? document.data(as: ExpenseRecord.self)).map(ItemRecord.expense)
        case .payments: (try? document.data(as: PaymentRecord.self)).map(ItemRecord.payment)
        }
    }

    // Only save once all parts arrived and the server confirmed our writes
    private func applyIfReady(_ tripID: UUID) {
        guard let accountID, let mirror = mirrors[tripID], !mirror.hasPendingWrites,
              let trip = mirror.trip(id: tripID, accountID: accountID) else { return }
        store?.applyRemote(trip)
    }

    private func stopListening(to tripID: UUID) {
        listListeners[tripID]?.forEach { $0.remove() }
        listListeners[tripID] = nil
        mirrors[tripID] = nil
    }

    private func report(_ error: Error?) {
        if let error = error as? FirestoreErrorCode, error.code == .permissionDenied {
            errorMessage = "Firestore refused access. Publish the rules in firestore.rules in the Firebase console."
        } else {
            errorMessage = error?.localizedDescription ?? "Unknown error."
        }
        updateStatus()
    }

    private func updateStatus() {
        guard accountID != nil else {
            status = .off
            return
        }
        let hasPendingWrites = mirrors.values.contains { $0.hasPendingWrites }
        if let errorMessage {
            status = .failed(errorMessage)
        } else if tripsAreFromCache {
            // Only offline if the server has answered before
            status = didUploadMissingTrips ? .offline : .connecting
        } else if hasPendingWrites {
            status = .uploading
        } else {
            status = .upToDate
        }
    }
}
