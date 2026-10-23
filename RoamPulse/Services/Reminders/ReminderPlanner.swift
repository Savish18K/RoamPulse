import Foundation

/// What the user chose in Settings → Notifications. Saved in UserDefaults.
struct ReminderSettings: Equatable {
    /// Packing reminder the evening before, and a reminder before each activity
    /// (only for trips with "Bedtime & packing reminders" on).
    var tripReminders = true
    /// How long before an activity its reminder appears.
    var minutesBefore = 30
    /// When the packing reminder appears the day before a trip, in minutes since midnight (19:00).
    var packingTime = 19 * 60
    /// Alerts when a new forecast puts an outdoor activity today or tomorrow at risk.
    var weatherAlerts = true

    static let minutesBeforeChoices = [15, 30, 60, 120]

    private enum Key {
        static let tripReminders = "reminders.trip"
        static let minutesBefore = "reminders.minutesBefore"
        static let packingTime = "reminders.packingTime"
        static let weatherAlerts = "smartAdvisories"
    }

    init() {}

    init(defaults: UserDefaults) {
        if defaults.object(forKey: Key.tripReminders) != nil { tripReminders = defaults.bool(forKey: Key.tripReminders) }
        if defaults.object(forKey: Key.minutesBefore) != nil { minutesBefore = defaults.integer(forKey: Key.minutesBefore) }
        if defaults.object(forKey: Key.packingTime) != nil { packingTime = defaults.integer(forKey: Key.packingTime) }
        if defaults.object(forKey: Key.weatherAlerts) != nil { weatherAlerts = defaults.bool(forKey: Key.weatherAlerts) }
    }

    func save(to defaults: UserDefaults) {
        defaults.set(tripReminders, forKey: Key.tripReminders)
        defaults.set(minutesBefore, forKey: Key.minutesBefore)
        defaults.set(packingTime, forKey: Key.packingTime)
        defaults.set(weatherAlerts, forKey: Key.weatherAlerts)
    }
}

/// One local notification the app wants to exist.
struct PlannedReminder: Hashable, Identifiable {
    /// Stable per thing reminded about (e.g. one per activity), so a change replaces the old
    /// notification instead of adding a second one.
    var id: String
    var title: String
    var body: String
    var fireDate: Date
    var tripID: UUID
}

/// Works out which reminders should be scheduled. A pure function of the trips, settings and time,
/// so every rule is unit tested. `ReminderService` then makes the system's list match.
enum ReminderPlanner {
    static let idPrefix = "roampulse."
    /// iOS keeps at most 64 pending notifications per app; leave room for weather alerts.
    static let maxScheduled = 60

    static func packingID(_ tripID: UUID) -> String { "\(idPrefix)packing.\(tripID.uuidString)" }
    static func activityID(_ activityID: UUID) -> String { "\(idPrefix)activity.\(activityID.uuidString)" }
    static func isScheduledReminder(_ id: String) -> Bool {
        id.hasPrefix("\(idPrefix)packing.") || id.hasPrefix("\(idPrefix)activity.")
    }

    /// Everything that should be scheduled now, soonest first.
    static func plan(trips: [Trip], settings: ReminderSettings, now: Date) -> [PlannedReminder] {
        guard settings.tripReminders else { return [] }
        let reminders = trips.filter(\.remindersOn).flatMap { trip in
            [packingReminder(for: trip, settings: settings, now: now)].compactMap { $0 }
                + activityReminders(for: trip, settings: settings, now: now)
        }
        return Array(reminders.sorted { $0.fireDate < $1.fireDate }.prefix(maxScheduled))
    }

    /// The evening before the trip, with how much is packed.
    static func packingReminder(for trip: Trip, settings: ReminderSettings, now: Date) -> PlannedReminder? {
        let calendar = Calendar.trip
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: trip.startDate)) else {
            return nil
        }
        let fireDate = calendar.date(dayBefore, atMinutes: settings.packingTime)
        guard fireDate > now else { return nil }

        let left = trip.packing.count - trip.packedCount
        let body = left > 0
            ? "\(trip.name) starts tomorrow. \(left) of \(trip.packing.count) items still to pack."
            : "\(trip.name) starts tomorrow. Everything is packed. Have a great trip!"
        return PlannedReminder(id: packingID(trip.id), title: "Time to pack", body: body, fireDate: fireDate, tripID: trip.id)
    }

    /// `minutesBefore` each activity that hasn't happened or been ticked off yet.
    static func activityReminders(for trip: Trip, settings: ReminderSettings, now: Date) -> [PlannedReminder] {
        trip.activities.compactMap { activity in
            guard !activity.isDone else { return nil }
            let start = WeatherAdvisor.startDate(of: activity, in: trip)
            let fireDate = start.addingTimeInterval(-Double(settings.minutesBefore) * 60)
            guard fireDate > now else { return nil }
            let place = activity.place.isEmpty ? "" : " at \(activity.place)"
            return PlannedReminder(
                id: activityID(activity.id),
                title: activity.title,
                body: "Starts at \(activity.timeText)\(place) (in \(minutesText(settings.minutesBefore))). \(trip.name), Day \(activity.day).",
                fireDate: fireDate,
                tripID: trip.id
            )
        }
    }

    /// Weather alerts to send now: outdoor activities today or tomorrow that a new forecast puts at risk.
    /// Each alert has an id per activity and time window, so the same warning is never sent twice.
    static func weatherAlerts(for trip: Trip, snapshot: WeatherSnapshot, now: Date,
                              alreadySent: Set<String>) -> [PlannedReminder] {
        let calendar = Calendar.trip
        guard let tomorrowEnd = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) else {
            return []
        }
        return WeatherAdvisor.advisories(for: trip, snapshot: snapshot).compactMap { advisory in
            guard let activity = trip.activities.first(where: { $0.id == advisory.activityID }) else { return nil }
            let start = WeatherAdvisor.startDate(of: activity, in: trip)
            guard start > now, start < tomorrowEnd else { return nil }
            let id = "\(idPrefix)weather.\(activity.id.uuidString).\(Int(advisory.windowStart.timeIntervalSince1970))"
            guard !alreadySent.contains(id) else { return nil }
            let when = calendar.isDate(start, inSameDayAs: now) ? "Today" : "Tomorrow"
            return PlannedReminder(
                id: id,
                title: "\(advisory.title) • \(when)",
                body: "\(activity.title) at \(activity.timeText): \(advisory.message)",
                fireDate: now,
                tripID: trip.id
            )
        }
    }

    static func minutesText(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min")
    }
}
