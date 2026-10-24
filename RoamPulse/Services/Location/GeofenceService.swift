import CoreLocation
import Foundation
import Observation

// What CLMonitor does, behind a protocol so tests can fake an arrival
protocol RegionMonitoring: AnyObject, Sendable {
    func monitoredIDs() async -> [String]
    func add(_ fence: Geofence) async
    func remove(_ id: String) async
    // ids of the regions the user walks into
    func arrivals() async -> AsyncStream<String>
}

// Geofencing with CLMonitor (iOS 17+). iOS keeps watching the regions after the app
// is closed and opens it in the background when one is entered
actor CoreLocationRegionMonitor: RegionMonitoring {
    private var monitorTask: Task<CLMonitor, Never>?

    // Only one CLMonitor per name is allowed, so it's made once and reused
    private func monitor() async -> CLMonitor {
        if let monitorTask { return await monitorTask.value }
        let task = Task { await CLMonitor("RoamPulseArrivals") }
        monitorTask = task
        return await task.value
    }

    func monitoredIDs() async -> [String] {
        await monitor().identifiers
    }

    func add(_ fence: Geofence) async {
        let condition = CLMonitor.CircularGeographicCondition(center: fence.coordinate, radius: fence.radius)
        await monitor().add(condition, identifier: fence.id, assuming: .unsatisfied)
    }

    func remove(_ id: String) async {
        await monitor().remove(id)
    }

    func arrivals() async -> AsyncStream<String> {
        let monitor = await monitor()
        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await event in await monitor.events where event.state == .satisfied {
                        continuation.yield(event.identifier)
                    }
                } catch {
                    // The stream only ends if monitoring stops
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// For previews, never watches anything
final class NoRegionMonitor: RegionMonitoring {
    func monitoredIDs() async -> [String] { [] }
    func add(_ fence: Geofence) async {}
    func remove(_ id: String) async {}
    func arrivals() async -> AsyncStream<String> { AsyncStream { $0.finish() } }
}

// Arrival alerts: watches the places on today's and tomorrow's plan and
// sends a notification when the user gets to one
@MainActor
@Observable
final class GeofenceService {
    private(set) var fences: [Geofence] = []

    @ObservationIgnored private let monitor: RegionMonitoring
    @ObservationIgnored private let location: LocationAuthorizing
    @ObservationIgnored private let reminders: ReminderService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private var listener: Task<Void, Never>?
    private static let savedKey = "geofences.watching"

    init(monitor: RegionMonitoring, location: LocationAuthorizing, reminders: ReminderService,
         defaults: UserDefaults = .standard, clock: Clock) {
        self.monitor = monitor
        self.location = location
        self.reminders = reminders
        self.defaults = defaults
        self.clock = clock
        if let data = defaults.data(forKey: Self.savedKey) {
            fences = (try? JSONDecoder().decode([Geofence].self, from: data)) ?? []
        }
    }

    var isOn: Bool { reminders.settings.arrivalAlerts && location.canMonitorRegions }

    func fences(for tripID: UUID) -> [Geofence] {
        fences.filter { $0.tripID == tripID }
    }

    // Called at launch, including when iOS opens the app in the background for an arrival
    func start() {
        guard listener == nil else { return }
        let monitor = monitor
        listener = Task { [weak self] in
            for await id in await monitor.arrivals() {
                await self?.handleArrival(id)
            }
        }
    }

    // Makes the watched regions match the plan, or clears them if alerts are off
    func update(trips: [Trip]) async {
        let wanted = isOn ? GeofencePlanner.plan(trips: trips, now: clock.now) : []
        let old = Dictionary(fences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let watched = Set(await monitor.monitoredIDs())
        let wantedIDs = Set(wanted.map(\.id))

        for id in watched where !wantedIDs.contains(id) {
            await monitor.remove(id)
        }
        // Adding again with the same id replaces it, e.g. after the place was moved
        for fence in wanted where !watched.contains(fence.id) || old[fence.id] != fence {
            await monitor.add(fence)
        }
        save(wanted)
    }

    func removeAll() async {
        for id in await monitor.monitoredIDs() {
            await monitor.remove(id)
        }
        save([])
    }

    // Backup while the app is open. CLMonitor doesn't fire in the Simulator (it reports
    // circles as unsupported there), so each new location is checked against the fences too.
    // Sending the same alert twice is already prevented in ReminderService
    func checkArrival(at location: CLLocation) async {
        for fence in GeofencePlanner.fences(containing: location, in: fences) {
            await handleArrival(fence.id)
        }
    }

    func handleArrival(_ id: String) async {
        guard reminders.settings.arrivalAlerts, let fence = fences.first(where: { $0.id == id }) else { return }
        await reminders.sendArrivalAlert(for: fence)
    }

    private func save(_ fences: [Geofence]) {
        self.fences = fences
        defaults.set(try? JSONEncoder().encode(fences), forKey: Self.savedKey)
    }
}
