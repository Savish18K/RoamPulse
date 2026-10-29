import CoreLocation
import Foundation
@testable import RoamPulse

// Fakes for Firebase, network, notifications and Face ID so tests run offline

@MainActor
final class FakeAuthService: AuthService {
    private(set) var currentUser: AppUser?
    private var onChange: ((AppUser?) -> Void)?
    private var accounts: [String: (password: String, user: AppUser)] = [:]
    private(set) var resetEmails: [String] = []
    private(set) var deletedAccounts: [String] = []
    // Next call fails with this
    var nextError: AuthError?

    func addAccount(name: String, email: String, password: String) -> AppUser {
        let user = AppUser(uid: "uid-\(accounts.count + 1)", email: email, displayName: name)
        accounts[email] = (password, user)
        return user
    }

    func observeUser(_ onChange: @escaping (AppUser?) -> Void) {
        self.onChange = onChange
        onChange(currentUser)
    }

    func signUp(name: String, email: String, password: String) async throws -> AppUser {
        try throwNextError()
        guard accounts[email] == nil else { throw AuthError.emailAlreadyInUse }
        let user = addAccount(name: name, email: email, password: password)
        // Like Firebase, the user arrives before the name is saved
        setUser(AppUser(uid: user.uid, email: email, displayName: nil))
        return user
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        try throwNextError()
        guard let account = accounts[email], account.password == password else { throw AuthError.wrongCredentials }
        setUser(account.user)
        return account.user
    }

    func sendPasswordReset(to email: String) async throws {
        try throwNextError()
        resetEmails.append(email)
    }

    func signOut() throws {
        setUser(nil)
    }

    func updateDisplayName(_ name: String) async throws -> AppUser {
        try throwNextError()
        guard var user = currentUser else { throw AuthError.notConfigured }
        user.displayName = name
        accounts[user.email] = (accounts[user.email]?.password ?? "", user)
        currentUser = user
        return user
    }

    func reauthenticate(password: String) async throws {
        try throwNextError()
        guard let user = currentUser, accounts[user.email]?.password == password else {
            throw AuthError.wrongCredentials
        }
    }

    func deleteAccount() async throws {
        try throwNextError()
        guard let user = currentUser else { return }
        accounts[user.email] = nil
        deletedAccounts.append(user.uid)
        setUser(nil)
    }

    // Like Firebase remembering the last sign in
    func restoreSession(_ user: AppUser) {
        currentUser = user
    }

    private func setUser(_ user: AppUser?) {
        currentUser = user
        onChange?(user)
    }

    private func throwNextError() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }
}

// Records uploads instead of using Firestore
@MainActor
final class RecordingSyncService: SyncService {
    private(set) var status: SyncStatus = .off
    private(set) var startedAccounts: [String] = []
    private(set) var stopCount = 0
    private(set) var changes: [(old: Trip?, new: Trip?)] = []
    private(set) var leftTrips: [UUID] = []
    private(set) var joined: [(invite: TripInvite, memberID: String?, name: String)] = []
    private(set) var cloudDataDeleted: [UUID] = []
    var invites: [String: TripInvite] = [:]
    // e.g. .offline
    var sharingError: SharingError?
    var now = Calendar.trip.date(2026, 12, 13, 16, 40)

    func start(accountID: String, store: TripStore) {
        startedAccounts.append(accountID)
        status = .upToDate
    }

    func stop() {
        stopCount += 1
        status = .off
    }

    func tripDidChange(from old: Trip?, to new: Trip?) {
        changes.append((old, new))
    }

    func createInvite(for trip: Trip, ownerName: String) async throws -> TripInvite {
        if let sharingError { throw sharingError }
        let invite = InviteCode.makeInvite(for: trip, code: "K7QM2XHA", ownerName: ownerName,
                                           accountID: startedAccounts.last ?? "uid-test", now: now)
        invites[invite.code] = invite
        return invite
    }

    func findInvite(code: String) async throws -> TripInvite {
        if let sharingError { throw sharingError }
        guard let code = InviteCode.normalized(code), let invite = invites[code] else { throw SharingError.inviteNotFound }
        guard !invite.isExpired(at: now) else { throw SharingError.inviteExpired }
        return invite
    }

    func joinTrip(_ invite: TripInvite, as memberID: String?, name: String, initials: String) async throws {
        if let sharingError { throw sharingError }
        joined.append((invite, memberID, name))
    }

    func leaveTrip(_ trip: Trip) {
        leftTrips.append(trip.id)
    }

    func deleteCloudData(for trips: [Trip]) async throws {
        if let sharingError { throw sharingError }
        cloudDataDeleted = trips.map(\.id)
    }
}

// One in-memory database per account
final class AccountDatabases {
    private(set) var repositories: [String: InMemoryTripRepository] = [:]
    private(set) var deleted: [String] = []

    func open(_ accountID: String) -> TripRepository {
        if let repository = repositories[accountID] {
            return repository
        }
        let repository = InMemoryTripRepository()
        repositories[accountID] = repository
        return repository
    }

    func delete(_ accountID: String) {
        repositories[accountID] = nil
        deleted.append(accountID)
    }
}

@MainActor
final class FakeNotificationScheduler: NotificationScheduling {
    var currentPermission: NotificationPermission = .notDetermined
    var answer = true
    private(set) var permissionRequests = 0
    private(set) var pending: [String: PlannedReminder] = [:]
    private(set) var delivered: [PlannedReminder] = []

    func permission() async -> NotificationPermission { currentPermission }

    func requestPermission() async -> Bool {
        permissionRequests += 1
        currentPermission = answer ? .allowed : .denied
        return answer
    }

    func pendingIdentifiers() async -> [String] { Array(pending.keys) }

    func schedule(_ reminder: PlannedReminder, immediately: Bool) async throws {
        if immediately {
            delivered.append(reminder)
        } else {
            pending[reminder.id] = reminder
        }
    }

    func removePending(_ identifiers: [String]) {
        for id in identifiers { pending[id] = nil }
    }
}

@MainActor
final class FakeAuthenticator: DeviceAuthenticating {
    var biometry: Biometry = .faceID
    var hasPasscode = true
    // nil means success
    var nextError: AppLockError?
    private(set) var attempts = 0

    func canAuthenticate() -> Bool { hasPasscode }

    func authenticate(reason: String) async throws {
        attempts += 1
        if let error = nextError {
            nextError = nil
            throw error
        }
    }
}

final class MutableClock: Clock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }

    func advance(minutes: Double) {
        now = now.addingTimeInterval(minutes * 60)
    }
}

// Returns saved JSON instead of using the network
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    // e.g. "/data/2.5/weather"
    var responses: [String: (status: Int, body: Data)] = [:]
    // e.g. no connection
    var error: URLError?
    private(set) var requestedPaths: [String] = []

    func data(from url: URL) async throws -> (Data, URLResponse) {
        let (error, response) = lock.withLock {
            requestedPaths.append(url.path())
            return (self.error, responses[url.path()])
        }
        if let error { throw error }
        let (status, body) = response ?? (404, Data())
        let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, http)
    }

    func count(_ path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestedPaths.filter { $0 == path }.count
    }
}

// Stop writes a small file like a real recording
@MainActor
final class FakeRecorder: AudioRecording {
    var allowsMicrophone = true
    // Stopping gives no file, like a recording that couldn't be finished
    var failsToStop = false
    private(set) var isRecording = false
    var elapsed: TimeInterval = 0
    var levels: [Double] = [0.2, 0.5]
    private(set) var discardCount = 0

    func requestPermission() async -> Bool { allowsMicrophone }

    func start() throws {
        isRecording = true
        elapsed = 0
    }

    func stop() -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        if failsToStop { return nil }
        let file = FileManager.default.temporaryDirectory.appending(path: "fake-recording-\(UUID().uuidString).m4a")
        try? Data("fake audio".utf8).write(to: file)
        return file
    }

    func discard() {
        isRecording = false
        discardCount += 1
    }
}

final class FakeTranscriber: SpeechTranscribing, @unchecked Sendable {
    var result: Result<String, TranscriptionError>
    private(set) var calls = 0

    init(_ result: Result<String, TranscriptionError>) {
        self.result = result
    }

    func transcribe(_ recording: URL, locale: Locale) async throws -> String {
        calls += 1
        return try result.get()
    }
}

// Pretends to be CLMonitor, arrive(at:) acts like walking into a region
final class FakeRegionMonitor: RegionMonitoring, @unchecked Sendable {
    private(set) var regions: [String: Geofence] = [:]
    private(set) var addCount = 0
    private var continuation: AsyncStream<String>.Continuation?

    func monitoredIDs() async -> [String] { Array(regions.keys) }

    func add(_ fence: Geofence) async {
        regions[fence.id] = fence
        addCount += 1
    }

    func remove(_ id: String) async { regions[id] = nil }

    func arrivals() async -> AsyncStream<String> {
        AsyncStream { continuation = $0 }
    }

    func arrive(at id: String) {
        continuation?.yield(id)
    }
}

@MainActor
final class FakeLocationPermission: LocationAuthorizing {
    var canMonitorRegions = true
}

// Returns saved results per query instead of searching MapKit
final class FakePlaceSearch: PlaceSearching, @unchecked Sendable {
    var results: [String: [MapPlace]] = [:]
    private(set) var queries: [String] = []

    func search(_ query: String, near center: CLLocationCoordinate2D?) async throws -> [MapPlace] {
        queries.append(query)
        return results[query] ?? []
    }
}

// Gives back prepared results in order, one per photo, instead of running the model
final class FakeLandmarkRecognizer: LandmarkRecognizing, @unchecked Sendable {
    var results: [RecognitionResult]
    var error: Error?
    private(set) var calls = 0

    init(_ results: [RecognitionResult] = []) {
        self.results = results
    }

    func recognize(_ imageData: Data) async throws -> RecognitionResult {
        calls += 1
        if let error { throw error }
        return results.isEmpty ? RecognitionResult(candidates: [], sceneTags: []) : results.removeFirst()
    }
}

// Keeps what the widget would have been sent instead of writing to the App Group
final class FakeWidgetStore: WidgetStoring {
    private(set) var saves: [WidgetSnapshot?] = []

    func save(_ snapshot: WidgetSnapshot?) throws {
        saves.append(snapshot)
    }
}
