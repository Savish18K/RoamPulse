import Foundation
import Observation
import UserNotifications

// Creates all the services once and passes them to the view models
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
    let recorder: AudioRecording
    let voice: VoiceJournalService
    let location: LocationService
    let geofences: GeofenceService
    let places: PlaceSearching
    // My Create ML landmark model, run with Vision
    let landmarkRecognizer: LandmarkRecognizing
    let notificationDelegate = NotificationDelegate()

    init(clock: Clock, auth: AuthService, sync: SyncService, isCloudAvailable: Bool,
         openRepository: @escaping (String) throws -> TripRepository,
         deleteLocalData: @escaping (String) throws -> Void = { _ in },
         makeWeather: (TripStore) -> WeatherService,
         notifications: NotificationScheduling,
         authenticator: DeviceAuthenticating,
         transcriber: SpeechTranscribing = OnDeviceTranscriber(),
         regionMonitor: RegionMonitoring = NoRegionMonitor(),
         places: PlaceSearching = NoPlaceSearch(),
         landmarkRecognizer: LandmarkRecognizing = VisionLandmarkRecognizer(),
         defaults: UserDefaults = .standard) {
        self.clock = clock
        self.auth = auth
        self.sync = sync
        // Empty until someone signs in
        let store = TripStore(repository: InMemoryTripRepository(), clock: clock)
        self.store = store
        self.weather = makeWeather(store)
        self.session = AppSession(auth: auth, store: store, sync: sync, isCloudAvailable: isCloudAvailable,
                                  openRepository: openRepository, deleteLocalData: deleteLocalData)
        self.reminders = ReminderService(scheduler: notifications, defaults: defaults, clock: clock)
        self.appLock = AppLock(authenticator: authenticator, clock: clock, defaults: defaults)
        self.recorder = AVAudioRecorderService()
        self.voice = VoiceJournalService(store: store, transcriber: transcriber)
        self.location = LocationService()
        self.geofences = GeofenceService(monitor: regionMonitor, location: location, reminders: reminders,
                                         defaults: defaults, clock: clock)
        self.places = places
        self.landmarkRecognizer = landmarkRecognizer
    }

    // Real services used by the app
    static func live() -> AppDependencies {
        // Firebase has to be configured first
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
            authenticator: LocalDeviceAuthenticator(),
            regionMonitor: CoreLocationRegionMonitor(),
            places: MapKitPlaceSearch()
        )

        // Arrivals can come in while the app is closed, so listen from launch
        let geofences = dependencies.geofences
        let store = dependencies.store
        if !FirebaseBootstrap.isRunningTests {
            geofences.start()
        }
        dependencies.location.onAuthorizationChange = {
            Task { await geofences.update(trips: store.trips) }
        }
        dependencies.location.onLocationUpdate = { location in
            Task { await geofences.checkArrival(at: location) }
        }

        // Send a weather alert when a new forecast puts an activity at risk
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

    var previewTripID: UUID { store.activeTrip?.id ?? store.trips.first?.id ?? UUID() }
}
