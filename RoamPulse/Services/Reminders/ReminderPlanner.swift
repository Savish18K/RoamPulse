import Foundation

// Saved in UserDefaults
struct ReminderSettings: Equatable {
    var tripReminders = true
    var minutesBefore = 30
    // Minutes since midnight (19:00)
    var packingTime = 19 * 60
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

struct PlannedReminder: Hashable, Identifiable {
    // Same id replaces the old notification instead of adding another
    var id: String
    var title: String
    var body: String
    var fireDate: Date
    var tripID: UUID
}

// Pure function so the rules can be unit tested
enum ReminderPlanner {
    static let idPrefix = "roampulse."
    // iOS allows 64, leave some room for weather alerts
    static let maxScheduled = 60

    static func packingID(_ tripID: UUID) -> String { "\(idPrefix)packing.\(tripID.uuidString)" }
    static func activityID(_ activityID: UUID) -> String { "\(idPrefix)activity.\(activityID.uuidString)" }
    static func isScheduledReminder(_ id: String) -> Bool {
        id.hasPrefix("\(idPrefix)packing.") || id.hasPrefix("\(idPrefix)activity.")
    }

    static func plan(trips: [Trip], settings: ReminderSettings, now: Date) -> [PlannedReminder] {
        guard settings.tripReminders else { return [] }
        let reminders = trips.filter(\.remindersOn).flatMap { trip in
            [packingReminder(for: trip, settings: settings, now: now)].compactMap { $0 }
                + activityReminders(for: trip, settings: settings, now: now)
        }
        return Array(reminders.sorted { $0.fireDate < $1.fireDate }.prefix(maxScheduled))
    }

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

    // id per activity and time window so the same alert isn't sent twice
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
