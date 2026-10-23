import Foundation
import Observation

/// Who is signed in, and what happens when that changes.
///
/// - Signing in opens that account's own Core Data database, shows its trips and starts syncing.
/// - Creating an account also adds the sample trips, so there is something to explore.
/// - Signing out stops syncing and clears the screen. The account's database stays on the iPhone,
///   so journal memories (which are never uploaded) are still there after signing back in.
@MainActor
@Observable
final class AppSession {
    enum State: Equatable {
        /// Waiting for Firebase to say whether someone is signed in (a moment after launch).
        case starting
        case signedOut
        case signedIn(AppUser)
    }

    private(set) var state: State = .starting
    /// False when Firebase isn't set up, so the sign-in screen can explain why sign-in won't work.
    let isCloudAvailable: Bool

    @ObservationIgnored private let auth: AuthService
    @ObservationIgnored private let store: TripStore
    @ObservationIgnored private let sync: SyncService
    @ObservationIgnored private let openRepository: (String) throws -> TripRepository
    @ObservationIgnored private let deleteLocalData: (String) throws -> Void
    /// True while an account is being created, so the first time it is opened the sample trips are added.
    @ObservationIgnored private var isCreatingAccount = false

    /// - Parameters:
    ///   - openRepository: opens the database for an account id. The app opens a Core Data store per
    ///     account; tests return an in-memory repository.
    ///   - deleteLocalData: deletes an account's database from the iPhone (when the account is deleted).
    init(auth: AuthService, store: TripStore, sync: SyncService, isCloudAvailable: Bool,
         openRepository: @escaping (String) throws -> TripRepository,
         deleteLocalData: @escaping (String) throws -> Void = { _ in }) {
        self.auth = auth
        self.store = store
        self.sync = sync
        self.isCloudAvailable = isCloudAvailable
        self.openRepository = openRepository
        self.deleteLocalData = deleteLocalData
    }

    var user: AppUser? {
        if case .signedIn(let user) = state { user } else { nil }
    }

    /// Starts following sign-ins and sign-outs. Called once when the app launches.
    func start() {
        auth.observeUser { [weak self] user in
            self?.userDidChange(user)
        }
    }

    // MARK: - Actions

    func signIn(email: String, password: String) async throws {
        let user = try await auth.signIn(email: email, password: password)
        userDidChange(user)
    }

    func signUp(name: String, email: String, password: String) async throws {
        isCreatingAccount = true
        defer { isCreatingAccount = false }
        let user = try await auth.signUp(name: name, email: email, password: password)
        // Firebase may already have reported the new user (before its name was saved),
        // in which case the account is open and only the name needs updating.
        userDidChange(user)
        store.updateAccount(user)
        state = .signedIn(user)
    }

    func sendPasswordReset(to email: String) async throws {
        try await auth.sendPasswordReset(to: email)
    }

    func signOut() {
        do {
            try auth.signOut()
            userDidChange(nil)
        } catch {
            store.errorMessage = "Couldn't sign out. \(error.localizedDescription)"
        }
    }

    /// Settings → Name.
    func updateName(_ name: String) async throws {
        let user = try await auth.updateDisplayName(name)
        store.updateAccount(user)
        state = .signedIn(user)
    }

    /// Settings → Delete account. In this order, so nothing is left behind if a step fails:
    /// 1. check the password (Firebase only deletes accounts that signed in recently);
    /// 2. delete the account's trips from the cloud (needs a connection), leave shared trips;
    /// 3. delete the Firebase account;
    /// 4. delete the database on this iPhone (trips, journal memories and photos).
    func deleteAccount(password: String) async throws {
        guard let user else { return }
        try await auth.reauthenticate(password: password)
        try await sync.deleteCloudData(for: store.trips)
        try await auth.deleteAccount()
        closeAccount()
        state = .signedOut
        do {
            try deleteLocalData(user.uid)
        } catch {
            store.errorMessage = "Your account was deleted, but some data couldn't be removed from this iPhone. \(error.localizedDescription)"
        }
    }

    // MARK: - Opening and closing an account

    /// Called by the auth service, and after each action, so it must cope with the same user twice.
    private func userDidChange(_ user: AppUser?) {
        guard let user else {
            closeAccount()
            state = .signedOut
            return
        }
        guard self.user?.uid != user.uid else { return }
        openAccount(for: user)
    }

    private func openAccount(for user: AppUser) {
        closeAccount()
        do {
            store.open(repository: try openRepository(user.uid), user: user)
        } catch {
            store.errorMessage = "Couldn't open your trips on this iPhone. \(error.localizedDescription)"
        }
        // Sync starts before the sample trips are added, so they are uploaded too.
        store.sync = sync
        sync.start(accountID: user.uid, store: store)
        if isCreatingAccount && store.trips.isEmpty {
            store.loadSampleData()
        }
        state = .signedIn(user)
    }

    private func closeAccount() {
        sync.stop()
        store.close()
    }
}
