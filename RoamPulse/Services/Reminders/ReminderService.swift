import Foundation
import Observation
import UserNotifications

enum NotificationPermission: Equatable {
    case notDetermined
    case allowed
    case denied

    var title: String {
        switch self {
        case .notDetermined: "Not asked yet"
        case .allowed: "Allowed"
        case .denied: "Off"
        }
    }
}

// Protocol so tests don't schedule real notifications
@MainActor
protocol NotificationScheduling: AnyObject {
    func permission() async -> NotificationPermission
    func requestPermission() async -> Bool
    func pendingIdentifiers() async -> [String]
    // Same id replaces the existing one
    func schedule(_ reminder: PlannedReminder, immediately: Bool) async throws
    func removePending(_ identifiers: [String])
}

@MainActor
final class UserNotificationScheduler: NotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .allowed
        }
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func schedule(_ reminder: PlannedReminder, immediately: Bool) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = reminder.tripID.uuidString
        var info = ["tripID": reminder.tripID.uuidString]
        if let activityID = reminder.activityID {
            info["activityID"] = activityID.uuidString
        }
        content.userInfo = info

        let trigger: UNNotificationTrigger?
        if immediately {
            trigger = nil
        } else {
            let parts = Calendar.trip.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        }
        try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }

    func removePending(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

// Keeps the local notifications in sync with the trips
@MainActor
@Observable
final class ReminderService {
    private(set) var permission: NotificationPermission = .notDetermined
    var settings: ReminderSettings {
        didSet { settings.save(to: defaults) }
    }

    @ObservationIgnored private let scheduler: NotificationScheduling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: Clock
    private static let sentAlertsKey = "reminders.sentWeatherAlerts"
    private static let sentArrivalsKey = "reminders.sentArrivals"

    init(scheduler: NotificationScheduling, defaults: UserDefaults = .standard, clock: Clock) {
        self.scheduler = scheduler
        self.defaults = defaults
        self.clock = clock
        self.settings = ReminderSettings(defaults: defaults)
    }

    func refreshPermission() async {
        permission = await scheduler.permission()
    }

    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        await refreshPermission()
        if permission == .notDetermined {
            _ = await scheduler.requestPermission()
            await refreshPermission()
        }
        return permission == .allowed
    }

    func reschedule(trips: [Trip]) async {
        await refreshPermission()
        guard permission == .allowed else { return }

        let plan = ReminderPlanner.plan(trips: trips, settings: settings, now: clock.now)
        let wanted = Set(plan.map(\.id))
        let stale = await scheduler.pendingIdentifiers().filter { ReminderPlanner.isScheduledReminder($0) && !wanted.contains($0) }
        if !stale.isEmpty {
            scheduler.removePending(stale)
        }
        for reminder in plan {
            try? await scheduler.schedule(reminder, immediately: false)
        }
    }

    // So the next user doesn't get someone else's reminders
    func removeAll() async {
        let ours = await scheduler.pendingIdentifiers().filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
        scheduler.removePending(ours)
    }

    func sendWeatherAlerts(for trip: Trip, snapshot: WeatherSnapshot) async {
        guard settings.weatherAlerts, trip.remindersOn else { return }
        await refreshPermission()
        guard permission == .allowed else { return }

        var sent = Set(defaults.stringArray(forKey: Self.sentAlertsKey) ?? [])
        let alerts = ReminderPlanner.weatherAlerts(for: trip, snapshot: snapshot, now: clock.now, alreadySent: sent)
        for alert in alerts {
            try? await scheduler.schedule(alert, immediately: true)
            sent.insert(alert.id)
        }
        // Only keep the last 200 ids
        defaults.set(Array(sent.sorted().suffix(200)), forKey: Self.sentAlertsKey)
    }

    func sendArrivalAlert(for fence: Geofence) async {
        guard settings.arrivalAlerts else { return }
        await refreshPermission()
        guard permission == .allowed else { return }

        var sent = Set(defaults.stringArray(forKey: Self.sentArrivalsKey) ?? [])
        guard let alert = GeofencePlanner.arrivalAlert(for: fence, now: clock.now, alreadySent: sent) else { return }
        try? await scheduler.schedule(alert, immediately: true)
        sent.insert(alert.id)
        defaults.set(Array(sent.sorted().suffix(200)), forKey: Self.sentArrivalsKey)
    }
}

// Show reminders in the foreground and open the trip on tap
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var openTrip: ((UUID) -> Void)?
    // Arrival alerts open a new memory linked to the activity
    var openMemory: ((UUID, UUID) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let tripID = (info["tripID"] as? String).flatMap(UUID.init(uuidString:))
        let activityID = (info["activityID"] as? String).flatMap(UUID.init(uuidString:))
        let open = openTrip
        let openMemory = openMemory
        Task { @MainActor in
            if let tripID, let activityID {
                openMemory?(tripID, activityID)
            } else if let tripID {
                open?(tripID)
            }
            completionHandler()
        }
    }
}
