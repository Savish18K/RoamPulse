import CoreLocation
import Foundation
import Observation

@MainActor
protocol LocationAuthorizing: AnyObject {
    var canMonitorRegions: Bool { get }
}

// Location permission and the user's position (Core Location)
@MainActor
@Observable
final class LocationService: NSObject, LocationAuthorizing {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var current: CLLocation?
    // Lets the geofences update straight after the user answers the permission prompt
    @ObservationIgnored var onAuthorizationChange: (() -> Void)?
    @ObservationIgnored var onLocationUpdate: ((CLLocation) -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()
    // Who needs updates right now (the map, arrival alerts). They stop when nobody does
    @ObservationIgnored private var users: Set<String> = []

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 20
    }

    var isAllowed: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    var canMonitorRegions: Bool { isAllowed }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    var statusText: String {
        switch authorization {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While using the app"
        case .denied, .restricted: "Off"
        default: "Asked when needed"
        }
    }

    // Always is needed for alerts while the app is closed.
    // iOS shows "While Using" first and asks about Always again later
    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    func requestWhenInUse() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func startUpdating(for user: String) {
        users.insert(user)
        if isAllowed {
            manager.startUpdatingLocation()
        }
    }

    func stopUpdating(for user: String) {
        users.remove(user)
        if users.isEmpty {
            manager.stopUpdatingLocation()
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != self.authorization else { return }
            self.authorization = status
            if self.isAllowed && !self.users.isEmpty {
                manager.startUpdatingLocation()
            }
            self.onAuthorizationChange?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.current = location
            self.onLocationUpdate?(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No fix yet (e.g. indoors), the map just doesn't show a distance
    }
}
