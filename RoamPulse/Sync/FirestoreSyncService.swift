import FirebaseFirestore
import Foundation
import Observation

/// Keeps the account's trips in Cloud Firestore in step with Core Data.
///
/// **Up:** after `TripStore` saves a change, `tripDidChange` works out the documents that changed
/// (`TripChangeSet`) and sends them as one batch. Firestore applies the batch to its offline cache
/// straight away and uploads it when there is a connection, so this class needs no upload queue.
///
/// **Down:** one listener watches the account's trips, and each trip gets one listener per list
/// (members, activities, packing, expenses, payments). `RemoteTripMirror` collects what they report.
/// When every part has arrived and none still holds unconfirmed writes from this iPhone, the trip is
/// saved locally with `TripStore.applyRemote`.
///
/// Conflicts: the server keeps the last write it receives for each document, so if two devices change
/// the same expense, the later one wins; changes to different items don't affect each other.
@MainActor
@Observable
final class FirestoreSyncService: SyncService {
    private(set) var status: SyncStatus = .off

    /// Firestore allows at most 500 writes in one batch.
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

    // MARK: - Starting and stopping

    func start(accountID: String, store: TripStore) {
        stop()
        self.accountID = accountID
        self.store = store
        status = .connecting

        // Every trip this account is a member of. includeMetadataChanges also reports when a write
        // is confirmed by the server, or when the app goes offline, so the status stays correct.
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

    // MARK: - Up: changes made on this iPhone

    func tripDidChange(from old: Trip?, to new: Trip?) {
        guard let accountID else { return }
        let writes = TripChangeSet.writes(from: old, to: new, accountID: accountID, now: clock.now)
        upload(writes)
    }

    private func upload(_ writes: [SyncWrite]) {
        guard !writes.isEmpty else { return }
        // The trip's own document is always first, so it exists before its items (the security rules need it).
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
            // Offline, this completion only runs once the phone is back online, so nothing waits for it.
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
        case .setTrip(let id, let record):
            try batch.setData(from: record, forDocument: tripDocument(id))
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

    // MARK: - Down: changes from the cloud

    private func tripsChanged(_ snapshot: QuerySnapshot?, error: Error?) {
        guard let snapshot else {
            report(error)
            return
        }
        tripsAreFromCache = snapshot.metadata.isFromCache

        // A trip that left the query (deleted in the console, or this account removed from it):
        // stop listening but keep the copy on the iPhone, so nothing is lost by mistake.
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

        // The first answer from the server: upload any trip the cloud doesn't have yet, for example
        // one made before syncing started. Cached answers are skipped because they may be incomplete.
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
            // A document that can't be read (for example, edited by hand in the console) is skipped.
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

    /// Saves the cloud's copy of the trip on the iPhone once it is complete and confirmed by the server.
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

    // MARK: - Status

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
            // Firestore answers from its cache first; that only means "offline" once the server has answered before.
            status = didUploadMissingTrips ? .offline : .connecting
        } else if hasPendingWrites {
            status = .uploading
        } else {
            status = .upToDate
        }
    }
}
