import CoreData

// Core Data setup, each account gets its own SQLite file
final class PersistenceController {
    // Loaded once so tests can make lots of in-memory stores without warnings
    static let model: NSManagedObjectModel = {
        let bundle = Bundle(for: PersistenceController.self)
        guard let url = bundle.url(forResource: "RoamPulse", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("RoamPulse.momd is missing from the app bundle.")
        }
        return model
    }()

    let container: NSPersistentContainer

    private(set) var loadError: Error?

    convenience init(inMemory: Bool = false) {
        self.init(storeURL: inMemory ? URL(fileURLWithPath: "/dev/null") : nil)
    }

    // Application Support/Accounts/<uid>/RoamPulse.sqlite
    convenience init(accountID: String) {
        let folder = Self.folder(for: accountID)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.init(storeURL: folder.appending(path: "RoamPulse.sqlite"))
    }

    static func folder(for accountID: String) -> URL {
        URL.applicationSupportDirectory
            .appending(path: "Accounts", directoryHint: .isDirectory)
            .appending(path: folderName(for: accountID), directoryHint: .isDirectory)
    }

    // Used when the account is deleted, store must be closed first
    static func deleteStore(accountID: String) throws {
        let folder = folder(for: accountID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.destroyPersistentStore(at: folder.appending(path: "RoamPulse.sqlite"), type: .sqlite)
        try FileManager.default.removeItem(at: folder)
    }

    init(storeURL: URL?) {
        container = NSPersistentContainer(name: "RoamPulse", managedObjectModel: Self.model)
        if let storeURL {
            container.persistentStoreDescriptions.first?.url = storeURL
        }
        // Lightweight migration is on by default
        container.loadPersistentStores { [weak self] _, error in
            self?.loadError = error
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // Make sure the uid is a safe folder name
    static func folderName(for accountID: String) -> String {
        String(accountID.map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }
}
