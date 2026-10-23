import Foundation
@testable import RoamPulse

// Stand-ins for Firebase, the network, notifications and Face ID, so the tests run offline
// and give the same result every time.

// MARK: - Auth

/// Pretends to be Firebase Authentication, keeping accounts in a dictionary.
@MainActor
final class FakeAuthService: AuthService {
    private(set) var currentUser: AppUser?
    private var onChange: ((AppUser?) -> Void)?
    private var accounts: [String: (password: String, user: AppUser)] = [:]
    private(set) var resetEmails: [String] = []
    private(set) var deletedAccounts: [String] = []
    /// Set to make the next call fail with this error.
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
        // Like Firebase, the listener hears about the new user before its name has been saved.
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

    /// Signs someone in as if Firebase remembered them from the last launch.
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

// MARK: - Sync

/// Records what the store asks to upload instead of talking to Firestore.
@MainActor
final class RecordingSyncService: SyncService {
    private(set) var status: SyncStatus = .off
    private(set) var startedAccounts: [String] = []
    private(set) var stopCount = 0
    private(set) var changes: [(old: Trip?, new: Trip?)] = []
    private(set) var leftTrips: [UUID] = []
    private(set) var joined: [(invite: TripInvite, memberID: String?, name: String)] = []
    private(set) var cloudDataDeleted: [UUID] = []
    /// Invites that `findInvite` can find, by code.
    var invites: [String: TripInvite] = [:]
    /// Set to make sharing calls fail, e.g. `.offline`.
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

/// One in-memory database per account, like the app's one Core Data file per account.
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

// MARK: - Notifications

/// Pretends to be UNUserNotificationCenter.
@MainActor
final class FakeNotificationScheduler: NotificationScheduling {
    var currentPermission: NotificationPermission = .notDetermined
    /// What the user answers when asked.
    var answer = true
    private(set) var permissionRequests = 0
    /// Scheduled (not yet delivered) notifications by id.
    private(set) var pending: [String: PlannedReminder] = [:]
    /// Notifications shown straight away.
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

// MARK: - Face ID

/// Says yes or no instead of asking for Face ID.
@MainActor
final class FakeAuthenticator: DeviceAuthenticating {
    var biometry: Biometry = .faceID
    var hasPasscode = true
    /// The next attempt fails with this error; nil means it succeeds.
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

// MARK: - Clock

/// A clock the test can move forward.
final class MutableClock: Clock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }

    func advance(minutes: Double) {
        now = now.addingTimeInterval(minutes * 60)
    }
}

// MARK: - Network

/// Answers OpenWeatherMap requests with saved JSON instead of using the network.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    /// Response per API path, e.g. "/data/2.5/weather".
    var responses: [String: (status: Int, body: Data)] = [:]
    /// When set, every request fails with this (e.g. no connection).
    var error: URLError?
    private(set) var requestedPaths: [String] = []

    func data(from url: URL) async throws -> (Data, URLResponse) {
        lock.lock()
        requestedPaths.append(url.path())
        let error = error
        let response = responses[url.path()]
        lock.unlock()
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
