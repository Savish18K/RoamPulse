import Foundation
import Observation

// Handles sign in / sign out and opens the right database for each account
@MainActor
@Observable
final class AppSession {
    enum State: Equatable {
        case starting
        case signedOut
        case signedIn(AppUser)
    }

    private(set) var state: State = .starting
    let isCloudAvailable: Bool

    @ObservationIgnored private let auth: AuthService
    @ObservationIgnored private let store: TripStore
    @ObservationIgnored private let sync: SyncService
    @ObservationIgnored private let openRepository: (String) throws -> TripRepository
    @ObservationIgnored private let deleteLocalData: (String) throws -> Void
    // Used to add the sample trips to a brand new account
    @ObservationIgnored private var isCreatingAccount = false

    // openRepository lets tests pass an in-memory repo
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

    func start() {
        auth.observeUser { [weak self] user in
            self?.userDidChange(user)
        }
    }

    func signIn(email: String, password: String) async throws {
        let user = try await auth.signIn(email: email, password: password)
        userDidChange(user)
    }

    func signUp(name: String, email: String, password: String) async throws {
        isCreatingAccount = true
        defer { isCreatingAccount = false }
        let user = try await auth.signUp(name: name, email: email, password: password)
        // Firebase might have already sent the new user before the name was saved
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

    func updateName(_ name: String) async throws {
        let user = try await auth.updateDisplayName(name)
        store.updateAccount(user)
        state = .signedIn(user)
    }

    // Order matters: check password, remove cloud trips, delete Firebase account, then local data
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
            store.errorMessage = "Your account was deleted, but some data couldn't be removed from this \(Device.name). \(error.localizedDescription)"
        }
    }

    // Can be called with the same user twice
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
            store.errorMessage = "Couldn't open your trips on this \(Device.name). \(error.localizedDescription)"
        }
        // Start sync first so the sample trips get uploaded too
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
