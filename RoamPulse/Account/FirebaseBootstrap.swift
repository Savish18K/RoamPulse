import FirebaseCore
import FirebaseFirestore
import Foundation

enum FirebaseBootstrap {
    private static var isConfigured = false

    // Tests use fakes, so don't start Firebase there
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var hasConfigFile: Bool {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    }

    // Returns false if Firebase can't be used, must run before Auth or Firestore are touched
    static func configure() -> Bool {
        guard !isRunningTests, hasConfigFile else { return false }
        // Checking FirebaseApp.app() first logs a warning, so use a flag
        guard !isConfigured else { return true }
        isConfigured = true

        FirebaseApp.configure()

        // Offline cache so the app works without internet (100 MB is plenty, no photos synced)
        let settings = Firestore.firestore().settings
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: 100 * 1024 * 1024))
        Firestore.firestore().settings = settings
        return true
    }
}
