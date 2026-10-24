import CoreLocation
import Foundation
import MapKit

// A search result that can be pinned on an activity
struct MapPlace: Hashable, Identifiable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double

    var id: String { "\(name)|\(latitude)|\(longitude)" }

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

// MapKit search behind a protocol so tests don't need the network
protocol PlaceSearching {
    func search(_ query: String, near center: CLLocationCoordinate2D?) async throws -> [MapPlace]
}

struct MapKitPlaceSearch: PlaceSearching {
    func search(_ query: String, near center: CLLocationCoordinate2D?) async throws -> [MapPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address, .physicalFeature]
        if let center {
            // Look around the trip first, about 60 km across
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { item in
            let coordinate = item.location.coordinate
            return MapPlace(name: item.name ?? query,
                            address: item.address?.shortAddress ?? item.address?.fullAddress ?? "",
                            latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }
}

// Returns nothing, used by previews
struct NoPlaceSearch: PlaceSearching {
    func search(_ query: String, near center: CLLocationCoordinate2D?) async throws -> [MapPlace] { [] }
}

extension Activity {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension Trip {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // Somewhere to centre a search: the trip's own place, or the middle of its pinned activities
    var searchCenter: CLLocationCoordinate2D? {
        if let coordinate { return coordinate }
        let pinned = activities.compactMap(\.coordinate)
        guard !pinned.isEmpty else { return nil }
        let latitude = pinned.map(\.latitude).reduce(0, +) / Double(pinned.count)
        let longitude = pinned.map(\.longitude).reduce(0, +) / Double(pinned.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension CLLocationDistance {
    // e.g. 350 -> "350 m", 1240 -> "1.2 km", 152300 -> "152 km"
    var distanceText: String {
        if self < 1000 { return "\(Int((self / 10).rounded()) * 10) m" }
        if self < 100_000 { return String(format: "%.1f km", self / 1000) }
        return "\(Int(self / 1000).formatted()) km"
    }
}
