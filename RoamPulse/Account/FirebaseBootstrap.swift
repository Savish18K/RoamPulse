import FirebaseCore
import FirebaseFirestore
import Foundation

/// Starts Firebase when the app launches.
enum FirebaseBootstrap {
    private static var isConfigured = false

    /// True inside the unit-test host app. Tests never talk to Firebase: they use fakes.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// GoogleService-Info.plist comes from the Firebase console and tells the SDK which project to use.
    static var hasConfigFile: Bool {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    }

    /// Configures Firebase once. Returns false when it can't be used (no config file, or running tests),
    /// in which case the app shows the sign-in screen with a "not set up" message instead of crashing.
    ///
    /// This has to run before anything calls `Auth.auth()` or `Firestore.firestore()`.
    static func configure() -> Bool {
        guard !isRunningTests, hasConfigFile else { return false }
        // A flag rather than `FirebaseApp.app() == nil`, which logs a "not configured" warning when asked first.
        guard !isConfigured else { return true }
        isConfigured = true

        FirebaseApp.configure()

        // Firestore keeps a copy of the data and any unsent writes on the iPhone, so the app works
        // offline and uploads changes later. 100 MB is plenty for trip data (no photos are synced).
        let settings = Firestore.firestore().settings
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: 100 * 1024 * 1024))
        Firestore.firestore().settings = settings
        return true
    }
}
