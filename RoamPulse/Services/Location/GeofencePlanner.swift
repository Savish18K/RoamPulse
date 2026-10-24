import CoreLocation
import Foundation

// A circle around one planned activity. Saved to UserDefaults so an arrival
// can still be handled when iOS wakes the app up in the background
struct Geofence: Codable, Hashable, Identifiable {
    var id: String
    var tripID: UUID
    var activityID: UUID
    var title: String
    var place: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var start: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// Pure functions so the rules can be unit tested
enum GeofencePlanner {
    static let idPrefix = "roampulse.arrival."
    // iOS only lets one app watch 20 regions at a time
    static let maxRegions = 20
    // Big enough for GPS drift, small enough to mean "you're there"
    static let radius: CLLocationDistance = 150

    static func id(for activityID: UUID) -> String { idPrefix + activityID.uuidString }

    // Today's and tomorrow's activities that aren't done yet and are pinned on the map
    static func plan(trips: [Trip], now: Date) -> [Geofence] {
        let calendar = Calendar.trip
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 2, to: today) else { return [] }

        let fences = trips.filter(\.remindersOn).flatMap { trip in
            trip.activities.compactMap { activity -> Geofence? in
                guard !activity.isDone, let latitude = activity.latitude, let longitude = activity.longitude else {
                    return nil
                }
                let start = WeatherAdvisor.startDate(of: activity, in: trip)
                guard start >= today, start < end else { return nil }
                return Geofence(id: id(for: activity.id), tripID: trip.id, activityID: activity.id,
                                title: activity.title, place: activity.place.isEmpty ? activity.title : activity.place,
                                latitude: latitude, longitude: longitude, radius: radius, start: start)
            }
        }
        return Array(fences.sorted { $0.start < $1.start }.prefix(maxRegions))
    }

    static func fences(containing location: CLLocation, in fences: [Geofence]) -> [Geofence] {
        fences.filter { fence in
            location.distance(from: CLLocation(latitude: fence.latitude, longitude: fence.longitude)) <= fence.radius
        }
    }

    // Only for today's plan, a fence left over from yesterday shouldn't fire
    static func arrivalAlert(for fence: Geofence, now: Date, alreadySent: Set<String>) -> PlannedReminder? {
        guard Calendar.trip.isDate(fence.start, inSameDayAs: now) else { return nil }
        let id = "\(fence.id).\(Int(fence.start.timeIntervalSince1970))"
        guard !alreadySent.contains(id) else { return nil }

        let time = Calendar.trip.minutesSinceMidnight(fence.start).clockText
        return PlannedReminder(
            id: id,
            title: "You're at \(fence.place)",
            body: "\(fence.title) is on today's plan at \(time). Tap to save a memory here.",
            fireDate: now,
            tripID: fence.tripID,
            activityID: fence.activityID
        )
    }
}
