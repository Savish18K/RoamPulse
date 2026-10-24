import Foundation
import Testing
@testable import RoamPulse

@MainActor
struct AccountTests {
    let now = Calendar.trip.date(2026, 12, 13, 16, 40)
    let auth = FakeAuthService()
    let sync = RecordingSyncService()
    let databases = AccountDatabases()

    private func makeSession() -> (session: AppSession, store: TripStore) {
        let store = TripStore(repository: InMemoryTripRepository(), clock: FixedClock(now: now))
        let session = AppSession(auth: auth, store: store, sync: sync, isCloudAvailable: true,
                                 openRepository: { [databases] in databases.open($0) },
                                 deleteLocalData: { [databases] in databases.delete($0) })
        session.start()
        return (session, store)
    }

    private func trip(_ name: String) -> Trip {
        Trip(name: name, destination: "Galle", startDate: now, endDate: now, budget: 0,
             members: [Member(name: "Me", colorHex: 0, isMe: true)], cover: .galleFort)
    }

    @Test(arguments: ["savishka@icloud.com", "a.b+trips@uni.ac.lk", "  padded@mail.com  "])
    func validEmailsPass(_ email: String) {
        #expect(AuthValidator.emailProblem(email) == nil)
    }

    @Test(arguments: ["", "savishka", "savishka@", "@icloud.com", "sav ishka@icloud.com", "savishka@icloud"])
    func invalidEmailsAreCaught(_ email: String) {
        #expect(AuthValidator.emailProblem(email) != nil)
    }

    @Test func newAccountsNeedEightCharacterPasswordsButSignInOnlyNeedsOne() {
        #expect(AuthValidator.passwordProblem("", isNewAccount: false) != nil)
        #expect(AuthValidator.passwordProblem("abc", isNewAccount: false) == nil)
        #expect(AuthValidator.passwordProblem("abc1234", isNewAccount: true) != nil)
        #expect(AuthValidator.passwordProblem("abc12345", isNewAccount: true) == nil)
        #expect(AuthValidator.nameProblem("   ") != nil)
        #expect(AuthValidator.nameProblem("Suu") == nil)
    }

    @Test func userNameFallsBackToTheEmail() {
        let named = AppUser(uid: "1", email: "savishka@icloud.com", displayName: "Savishka Kuruppu")
        #expect(named.name == "Savishka Kuruppu")
        #expect(named.firstName == "Savishka")
        #expect(named.initials == "SK")

        let unnamed = AppUser(uid: "2", email: "suu@mail.com", displayName: nil)
        #expect(unnamed.name == "suu")
        #expect(unnamed.initials == "SU")
    }

    @Test func nobodySignedInShowsTheSignInScreen() {
        let (session, store) = makeSession()
        #expect(session.state == .signedOut)
        #expect(store.trips.isEmpty)
        #expect(sync.startedAccounts.isEmpty)
    }

    @Test func aRememberedUserIsSignedInAtLaunch() {
        let user = auth.addAccount(name: "Suu Perera", email: "suu@mail.com", password: "password1")
        auth.restoreSession(user)
        let (session, store) = makeSession()

        #expect(session.state == .signedIn(user))
        #expect(store.profile == UserProfile(fullName: "Suu Perera", email: "suu@mail.com"))
        #expect(store.me.name == "Suu")
        #expect(store.me.userUID == user.uid)
        #expect(store.accountID == user.uid)
        #expect(sync.startedAccounts == [user.uid])
    }

    @Test func creatingAnAccountAddsAndUploadsTheSampleTrips() async throws {
        let (session, store) = makeSession()
        try await session.signUp(name: "Savishka Kuruppu", email: "savishka@icloud.com", password: "password1")

        #expect(session.user?.name == "Savishka Kuruppu")
        #expect(store.profile.fullName == "Savishka Kuruppu", "the name saved after sign-up replaces the email")
        #expect(store.trips.count == SampleData.make(now: now).trips.count)
        #expect(sync.changes.count == store.trips.count, "every sample trip is uploaded")
        #expect(sync.changes.allSatisfy { $0.old == nil })
        #expect(store.trips.allSatisfy { $0.ownerUID == session.user?.uid }, "the new account owns its trips")
    }

    @Test func signingInToAnExistingAccountDoesNotAddSampleTrips() async throws {
        _ = auth.addAccount(name: "Samee", email: "samee@mail.com", password: "password1")
        let (session, store) = makeSession()
        try await session.signIn(email: "samee@mail.com", password: "password1")

        #expect(session.user?.email == "samee@mail.com")
        #expect(store.trips.isEmpty)
        #expect(sync.changes.isEmpty)
    }

    @Test func signingOutClearsTheScreenAndSigningBackInRestoresTheTrips() async throws {
        let (session, store) = makeSession()
        try await session.signUp(name: "Suresha", email: "suresha@mail.com", password: "password1")
        store.addTrip(trip("Southern Coast"))
        let tripCount = store.trips.count

        session.signOut()
        #expect(session.state == .signedOut)
        #expect(store.trips.isEmpty)
        #expect(store.sync == nil)
        #expect(store.accountID == nil)
        #expect(sync.status == .off)

        try await session.signIn(email: "suresha@mail.com", password: "password1")
        #expect(store.trips.count == tripCount, "the account's database is kept on the iPhone")
    }

    @Test func twoAccountsNeverSeeEachOthersTrips() async throws {
        let (session, store) = makeSession()
        try await session.signUp(name: "Suu", email: "suu@mail.com", password: "password1")
        store.addTrip(trip("Suu's secret trip"))
        session.signOut()

        try await session.signUp(name: "Samee", email: "samee@mail.com", password: "password1")
        #expect(!store.trips.contains { $0.name == "Suu's secret trip" })
        #expect(databases.repositories.count == 2)
    }

    @Test func changingTheNameUpdatesTheProfile() async throws {
        let (session, store) = makeSession()
        try await session.signUp(name: "Savi", email: "savi@mail.com", password: "password1")
        try await session.updateName("Savishka Kuruppu")

        #expect(store.profile.fullName == "Savishka Kuruppu")
        #expect(store.me.initials == "SK")
        #expect(session.user?.displayName == "Savishka Kuruppu")
    }

    @Test func deletingTheAccountRemovesCloudDataTheAccountAndTheDatabase() async throws {
        let (session, store) = makeSession()
        try await session.signUp(name: "Suu", email: "suu@mail.com", password: "password1")
        let uid = try #require(session.user?.uid)
        let tripIDs = store.trips.map(\.id)

        try await session.deleteAccount(password: "password1")

        #expect(Set(sync.cloudDataDeleted) == Set(tripIDs), "cloud data goes first, while the account can still write")
        #expect(auth.deletedAccounts == [uid])
        #expect(databases.deleted == [uid])
        #expect(session.state == .signedOut)
        #expect(store.trips.isEmpty)
    }

    @Test func aWrongPasswordDeletesNothing() async throws {
        let (session, store) = makeSession()
        try await session.signUp(name: "Suu", email: "suu@mail.com", password: "password1")

        await #expect(throws: AuthError.wrongCredentials) {
            try await session.deleteAccount(password: "not-my-password")
        }
        #expect(sync.cloudDataDeleted.isEmpty)
        #expect(auth.deletedAccounts.isEmpty)
        #expect(databases.deleted.isEmpty)
        #expect(!store.trips.isEmpty)
    }

    @Test func offlineTheAccountIsNotDeleted() async throws {
        let (session, _) = makeSession()
        try await session.signUp(name: "Suu", email: "suu@mail.com", password: "password1")
        sync.sharingError = .offline

        await #expect(throws: SharingError.offline) {
            try await session.deleteAccount(password: "password1")
        }
        #expect(auth.deletedAccounts.isEmpty, "never delete the account while its cloud data is still there")
        #expect(session.user != nil)
    }

    @Test func anIncompleteFormShowsProblemsAndSendsNothing() async {
        let (session, _) = makeSession()
        let form = AuthViewModel(session: session)
        form.mode = .signUp
        #expect(form.emailProblem == nil, "no red before the first try")

        form.email = "not-an-email"
        form.password = "short"
        await form.submit()

        #expect(form.nameProblem != nil)
        #expect(form.emailProblem != nil)
        #expect(form.passwordProblem != nil)
        #expect(session.state == .signedOut)
    }

    @Test func aWrongPasswordShowsAPlainMessage() async {
        _ = auth.addAccount(name: "Suu", email: "suu@mail.com", password: "password1")
        let (session, _) = makeSession()
        let form = AuthViewModel(session: session)
        form.email = "suu@mail.com"
        form.password = "wrong-password"
        await form.submit()

        #expect(form.errorMessage == AuthError.wrongCredentials.errorDescription)
        #expect(session.state == .signedOut)
        #expect(!form.isWorking)
    }

    @Test func signingInClearsThePassword() async {
        _ = auth.addAccount(name: "Suu", email: "suu@mail.com", password: "password1")
        let (session, _) = makeSession()
        let form = AuthViewModel(session: session)
        form.email = " suu@mail.com "
        form.password = "password1"
        await form.submit()

        #expect(session.user?.email == "suu@mail.com", "spaces around the email are ignored")
        #expect(form.password.isEmpty)
        #expect(form.errorMessage == nil)
    }

    @Test func passwordResetNeedsAValidEmail() async {
        let (session, _) = makeSession()
        let form = AuthViewModel(session: session)
        await form.sendPasswordReset()
        #expect(form.errorMessage != nil)
        #expect(auth.resetEmails.isEmpty)

        form.email = "suu@mail.com"
        await form.sendPasswordReset()
        #expect(auth.resetEmails == ["suu@mail.com"])
        #expect(form.infoMessage != nil)
    }

    @Test func switchingBetweenSignInAndSignUpClearsTheMessages() async {
        let (session, _) = makeSession()
        let form = AuthViewModel(session: session)
        auth.nextError = .network
        form.email = "suu@mail.com"
        form.password = "password1"
        await form.submit()
        #expect(form.errorMessage == AuthError.network.errorDescription)

        form.mode = .signUp
        #expect(form.errorMessage == nil)
        #expect(form.passwordProblem == nil)
    }
}
