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

/// The parts of `UNUserNotificationCenter` the app uses, behind a protocol so tests can record
/// what would be scheduled.
@MainActor
protocol NotificationScheduling: AnyObject {
    func permission() async -> NotificationPermission
    func requestPermission() async -> Bool
    func pendingIdentifiers() async -> [String]
    /// Schedules the reminder at its fire date, or shows it now when `immediately` is true.
    /// Scheduling an id that already exists replaces it.
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
        content.userInfo = ["tripID": reminder.tripID.uuidString]

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

/// Keeps the scheduled local notifications in step with the trips (UserNotifications).
///
/// Every time the trips or settings change, `reschedule` works out the reminders that should exist
/// (`ReminderPlanner`), removes ones that are no longer wanted (a deleted activity or trip) and adds or
/// replaces the rest. Ids are per activity/trip, so editing an activity's time replaces its reminder.
/// Nothing is ever asked for until the user turns a reminder on.
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

    init(scheduler: NotificationScheduling, defaults: UserDefaults = .standard, clock: Clock) {
        self.scheduler = scheduler
        self.defaults = defaults
        self.clock = clock
        self.settings = ReminderSettings(defaults: defaults)
    }

    func refreshPermission() async {
        permission = await scheduler.permission()
    }

    /// Asks for permission the first time; afterwards just reports the answer.
    /// Returns true when notifications are allowed.
    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        await refreshPermission()
        if permission == .notDetermined {
            _ = await scheduler.requestPermission()
            await refreshPermission()
        }
        return permission == .allowed
    }

    /// Makes the scheduled reminders match the trips.
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

    /// Removes every scheduled reminder, e.g. after signing out, so someone else's trips don't notify.
    func removeAll() async {
        let ours = await scheduler.pendingIdentifiers().filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
        scheduler.removePending(ours)
    }

    /// Called after a new forecast is downloaded: alerts about outdoor activities today or tomorrow
    /// that are now at risk. Each warning is only sent once.
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
        // Old ids can go; only the last 200 are needed to avoid repeats.
        defaults.set(Array(sent.sorted().suffix(200)), forKey: Self.sentAlertsKey)
    }
}

/// Shows reminders even while the app is open, and opens the trip when one is tapped.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Called with the trip of the tapped notification.
    var openTrip: ((UUID) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let tripID = (response.notification.request.content.userInfo["tripID"] as? String).flatMap(UUID.init(uuidString:))
        let open = openTrip
        Task { @MainActor in
            if let tripID {
                open?(tripID)
            }
            completionHandler()
        }
    }
}
