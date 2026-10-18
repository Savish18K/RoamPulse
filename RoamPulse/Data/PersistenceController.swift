import CoreData

/// Sets up the Core Data stack: the model and the SQLite database on the iPhone.
///
/// Every signed-in account has its own database file, so two people who sign in on the same
/// iPhone never see each other's trips, and signing out doesn't delete anything.
final class PersistenceController {
    /// The compiled model (RoamPulse.xcdatamodeld). It is loaded once and shared, so tests can
    /// create many in-memory stores without Core Data warning about duplicate entity classes.
    static let model: NSManagedObjectModel = {
        let bundle = Bundle(for: PersistenceController.self)
        guard let url = bundle.url(forResource: "RoamPulse", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("RoamPulse.momd is missing from the app bundle.")
        }
        return model
    }()

    let container: NSPersistentContainer

    /// Set when the database couldn't be opened. The app shows this instead of crashing.
    private(set) var loadError: Error?

    /// - Parameter inMemory: true for tests and previews, so nothing is written to disk.
    convenience init(inMemory: Bool = false) {
        self.init(storeURL: inMemory ? URL(fileURLWithPath: "/dev/null") : nil)
    }

    /// The database of one signed-in account: Application Support/Accounts/<uid>/RoamPulse.sqlite.
    convenience init(accountID: String) {
        let folder = URL.applicationSupportDirectory
            .appending(path: "Accounts", directoryHint: .isDirectory)
            .appending(path: Self.folderName(for: accountID), directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.init(storeURL: folder.appending(path: "RoamPulse.sqlite"))
    }

    /// - Parameter storeURL: where the SQLite file lives. nil uses Core Data's default location.
    init(storeURL: URL?) {
        container = NSPersistentContainer(name: "RoamPulse", managedObjectModel: Self.model)
        if let storeURL {
            container.persistentStoreDescriptions.first?.url = storeURL
        }
        // Lightweight migration is on by default, so adding an attribute later won't lose data.
        container.loadPersistentStores { [weak self] _, error in
            self?.loadError = error
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Firebase user ids are letters and digits; anything else is replaced so the id is a safe folder name.
    static func folderName(for accountID: String) -> String {
        String(accountID.map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }
}
