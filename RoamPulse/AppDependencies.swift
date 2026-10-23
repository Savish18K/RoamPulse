import Foundation
import Observation
import UserNotifications

/// Creates the app's services once and hands them out (dependency injection).
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
    let reminders: ReminderService
    let appLock: AppLock
    /// Shows reminders while the app is open and opens the trip when one is tapped.
    let notificationDelegate = NotificationDelegate()

    /// - Parameter makeWeather: builds the weather service once the store exists (it caches forecasts there).
    init(clock: Clock, auth: AuthService, sync: SyncService, isCloudAvailable: Bool,
         openRepository: @escaping (String) throws -> TripRepository,
         deleteLocalData: @escaping (String) throws -> Void = { _ in },
         makeWeather: (TripStore) -> WeatherService,
         notifications: NotificationScheduling,
         authenticator: DeviceAuthenticating,
         defaults: UserDefaults = .standard) {
        self.clock = clock
        self.auth = auth
        self.sync = sync
        // Empty until someone signs in and `session` opens their database.
        let store = TripStore(repository: InMemoryTripRepository(), clock: clock)
        self.store = store
        self.weather = makeWeather(store)
        self.session = AppSession(auth: auth, store: store, sync: sync, isCloudAvailable: isCloudAvailable,
                                  openRepository: openRepository, deleteLocalData: deleteLocalData)
        self.reminders = ReminderService(scheduler: notifications, defaults: defaults, clock: clock)
        self.appLock = AppLock(authenticator: authenticator, clock: clock, defaults: defaults)
    }

    /// The real app: Firebase sign-in and sync, a Core Data database per account, OpenWeatherMap
    /// (if an API key is set), local notifications, Face ID and the real time.
    static func live() -> AppDependencies {
        // Firebase must be configured before anything uses Auth or Firestore.
        let firebaseIsReady = FirebaseBootstrap.configure()
        let clock = SystemClock()
        let dependencies = AppDependencies(
            clock: clock,
            auth: firebaseIsReady ? FirebaseAuthService() : UnavailableAuthService(),
            sync: firebaseIsReady ? FirestoreSyncService(clock: clock) : NoSyncService(),
            isCloudAvailable: firebaseIsReady,
            openRepository: { accountID in try CoreDataTripRepository(accountID: accountID) },
            deleteLocalData: { accountID in try PersistenceController.deleteStore(accountID: accountID) },
            makeWeather: { store in
                guard let apiKey = OpenWeatherMapConfig.apiKey else { return MockWeatherService(clock: clock) }
                let service = OpenWeatherMapService(client: OpenWeatherMapClient(apiKey: apiKey), clock: clock)
                service.store = store
                return service
            },
            notifications: UserNotificationScheduler(),
            authenticator: LocalDeviceAuthenticator()
        )

        // A new forecast can put tomorrow's hike at risk: tell the user (once).
        if let liveWeather = dependencies.weather as? OpenWeatherMapService {
            let reminders = dependencies.reminders
            liveWeather.onNewForecast = { trip, snapshot in
                Task { await reminders.sendWeatherAlerts(for: trip, snapshot: snapshot) }
            }
        }
        if !FirebaseBootstrap.isRunningTests {
            UNUserNotificationCenter.current().delegate = dependencies.notificationDelegate
        }
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
            auth: PreviewAuthService(),
            sync: NoSyncService(),
            isCloudAvailable: true,
            openRepository: { _ in repository },
            makeWeather: { _ in MockWeatherService(clock: clock) },
            notifications: UserNotificationScheduler(),
            authenticator: LocalDeviceAuthenticator(),
            defaults: UserDefaults(suiteName: "preview") ?? .standard
        )
        dependencies.session.start()
        return dependencies
    }

    /// The active sample trip, for previews.
    var previewTripID: UUID { store.activeTrip?.id ?? store.trips.first?.id ?? UUID() }
}
