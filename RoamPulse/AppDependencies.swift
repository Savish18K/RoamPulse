import Foundation
import Observation

/// Creates the app's services once and hands them out (dependency injection).
///
/// Views read this from the environment and pass what each view model needs into the view
/// model's initialiser, so a view model never creates its own services. Tests and previews
/// build the same view models with stand-ins: an in-memory repository and a fixed clock.
@MainActor
@Observable
final class AppDependencies {
    let clock: Clock
    let weather: WeatherService
    let store: TripStore
    let auth: AuthService
    let sync: SyncService
    let session: AppSession

    init(clock: Clock, weather: WeatherService, auth: AuthService, sync: SyncService, isCloudAvailable: Bool,
         openRepository: @escaping (String) throws -> TripRepository) {
        self.clock = clock
        self.weather = weather
        self.auth = auth
        self.sync = sync
        // Empty until someone signs in and `session` opens their database.
        let store = TripStore(repository: InMemoryTripRepository(), clock: clock)
        self.store = store
        self.session = AppSession(auth: auth, store: store, sync: sync, isCloudAvailable: isCloudAvailable,
                                  openRepository: openRepository)
    }

    /// The real app: Firebase sign-in and sync, a Core Data database per account, and the real time.
    static func live() -> AppDependencies {
        // Firebase must be configured before anything uses Auth or Firestore.
        let firebaseIsReady = FirebaseBootstrap.configure()
        let clock = SystemClock()
        let dependencies = AppDependencies(
            clock: clock,
            weather: MockWeatherService(clock: clock),
            auth: firebaseIsReady ? FirebaseAuthService() : UnavailableAuthService(),
            sync: firebaseIsReady ? FirestoreSyncService(clock: clock) : NoSyncService(),
            isCloudAvailable: firebaseIsReady,
            openRepository: { accountID in try CoreDataTripRepository(accountID: accountID) }
        )
        dependencies.session.start()
        return dependencies
    }

    /// SwiftUI previews: signed in as the sample user, the sample trips in memory, nothing saved or synced.
    static func preview() -> AppDependencies {
        let clock = SystemClock()
        let sample = SampleData.make(now: clock.now)
        let repository = InMemoryTripRepository(trips: sample.trips, memories: sample.memories)
        let dependencies = AppDependencies(
            clock: clock,
            weather: MockWeatherService(clock: clock),
            auth: PreviewAuthService(),
            sync: NoSyncService(),
            isCloudAvailable: true,
            openRepository: { _ in repository }
        )
        dependencies.session.start()
        return dependencies
    }

    /// The active sample trip, for previews.
    var previewTripID: UUID { store.activeTrip?.id ?? store.trips.first?.id ?? UUID() }
}
