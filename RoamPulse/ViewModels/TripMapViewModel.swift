import CoreLocation
import Foundation
import MapKit
import Observation

struct MapPin: Identifiable {
    let activity: Activity
    let coordinate: CLLocationCoordinate2D
    let number: Int

    var id: UUID { activity.id }
}

// Trip map: the plan's places as numbered pins, one day or the whole trip
@MainActor
@Observable
final class TripMapViewModel {
    let tripID: UUID
    // nil shows the whole trip
    var selectedDay: Int? {
        didSet {
            if let selectedActivity, let selectedDay, selectedActivity.day != selectedDay {
                selectedActivityID = nil
            }
        }
    }
    var selectedActivityID: UUID?
    private(set) var isLocating = false
    private(set) var locateMessage: String?

    private let store: TripStore
    private let clock: Clock
    private let places: PlaceSearching
    // Search results further than this from the trip are probably a different place with the same name
    static let maxSearchDistance: CLLocationDistance = 100_000

    init(tripID: UUID, activityID: UUID? = nil, store: TripStore, clock: Clock, places: PlaceSearching) {
        self.tripID = tripID
        self.store = store
        self.clock = clock
        self.places = places

        let trip = store.trip(tripID)
        if let activity = trip?.activities.first(where: { $0.id == activityID }) {
            selectedDay = activity.day
            selectedActivityID = activity.id
        } else {
            // Today for an active trip, otherwise the whole trip
            selectedDay = trip?.dayNumber(at: clock.now)
        }
    }

    var trip: Trip? { store.trip(tripID) }

    var dayTitles: [String] {
        ["All"] + (1...max(trip?.dayCount ?? 1, 1)).map { "Day \($0)" }
    }

    // 0 is "All" in the segmented control
    var selectedDayIndex: Int {
        get { selectedDay ?? 0 }
        set { selectedDay = newValue == 0 ? nil : newValue }
    }

    // In plan order: by day, then time
    var shownActivities: [Activity] {
        guard let trip else { return [] }
        if let selectedDay {
            return trip.activities(onDay: selectedDay)
        }
        return trip.activities.sorted { ($0.day, $0.minutes, $0.title) < ($1.day, $1.minutes, $1.title) }
    }

    var pinned: [Activity] { shownActivities.filter(\.hasCoordinates) }

    var pins: [MapPin] {
        pinned.enumerated().compactMap { index, activity in
            activity.coordinate.map { MapPin(activity: activity, coordinate: $0, number: index + 1) }
        }
    }

    var unpinned: [Activity] { shownActivities.filter { !$0.hasCoordinates } }

    var selectedActivity: Activity? {
        trip?.activities.first { $0.id == selectedActivityID }
    }

    // Number shown on the pin, same order as the day's plan
    func number(of activity: Activity) -> Int {
        (pinned.firstIndex { $0.id == activity.id } ?? 0) + 1
    }

    var nextActivityID: UUID? { trip?.nextActivity(at: clock.now)?.id }

    // Dashed line through the day's stops, only drawn for a single day
    var dayRoute: [CLLocationCoordinate2D] {
        selectedDay == nil ? [] : pinned.compactMap(\.coordinate)
    }

    var region: MKCoordinateRegion? {
        Self.region(fitting: pinned.compactMap(\.coordinate))
            ?? Self.region(fitting: trip?.activities.compactMap(\.coordinate) ?? [])
            ?? trip?.coordinate.map { MKCoordinateRegion(center: $0, latitudinalMeters: 20_000, longitudinalMeters: 20_000) }
    }

    func subtitle(for activity: Activity) -> String {
        var parts = ["Day \(activity.day)", activity.timeText]
        if !activity.place.isEmpty && activity.place != activity.title {
            parts.append(activity.place)
        }
        return parts.joined(separator: " • ")
    }

    func distanceText(to activity: Activity, from location: CLLocation?) -> String? {
        guard let location, let latitude = activity.latitude, let longitude = activity.longitude else { return nil }
        let distance = location.distance(from: CLLocation(latitude: latitude, longitude: longitude))
        return "\(distance.distanceText) away"
    }

    func toggleVisited(_ activity: Activity) {
        store.updateTrip(tripID) { trip in
            guard let index = trip.activities.firstIndex(where: { $0.id == activity.id }) else { return }
            trip.activities[index].isDone.toggle()
        }
    }

    // Finds the shown activities that aren't on the map yet with MapKit search and saves where they are
    func locateMissing() async {
        guard let trip, !isLocating else { return }
        let missing = unpinned
        guard !missing.isEmpty else { return }
        isLocating = true
        defer { isLocating = false }

        let center = trip.searchCenter
        var found: [UUID: MapPlace] = [:]
        for activity in missing {
            if let place = await bestMatch(for: activity, near: center) {
                found[activity.id] = place
            }
        }

        if !found.isEmpty {
            store.updateTrip(tripID) { trip in
                for index in trip.activities.indices {
                    guard let place = found[trip.activities[index].id] else { continue }
                    trip.activities[index].latitude = place.latitude
                    trip.activities[index].longitude = place.longitude
                }
            }
        }
        locateMessage = found.count == missing.count
            ? "Found all \(missing.count) on the map."
            : "Found \(found.count) of \(missing.count). Edit the others to pick their place."
    }

    // Tries the activity's title first ("Nine Arch Bridge viewpoint"), then its place ("Ella")
    private func bestMatch(for activity: Activity, near center: CLLocationCoordinate2D?) async -> MapPlace? {
        var queries: [String] = []
        for text in [activity.title, activity.place].map(\.trimmed) where !text.isEmpty && !queries.contains(text) {
            queries.append(text)
        }
        let tripLocation = center.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }

        for query in queries {
            let results = (try? await places.search(query, near: center)) ?? []
            let nearby = results.first { result in
                guard let tripLocation else { return true }
                return result.location.distance(from: tripLocation) <= Self.maxSearchDistance
            }
            if let nearby { return nearby }
        }
        return nil
    }

    // Fits all the coordinates with some padding, nil if there are none
    static func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        // At least about 1 km across so a single pin isn't zoomed in to the street
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
                                    longitudeDelta: max((maxLon - minLon) * 1.5, 0.01))
        return MKCoordinateRegion(center: center, span: span)
    }
}
