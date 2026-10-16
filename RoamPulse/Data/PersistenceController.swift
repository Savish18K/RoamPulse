import CoreData

/// Sets up the Core Data stack: the model and the SQLite database on the iPhone.
final class PersistenceController {
    static let shared = PersistenceController()

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
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "RoamPulse", managedObjectModel: Self.model)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        // Lightweight migration is on by default, so adding an attribute later won't lose data.
        container.loadPersistentStores { [weak self] _, error in
            self?.loadError = error
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
