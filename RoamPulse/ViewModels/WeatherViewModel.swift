import Foundation
import Observation

@MainActor
@Observable
final class WeatherViewModel {
    let tripID: UUID
    private let store: TripStore
    private let weatherService: WeatherService

    private(set) var snapshot: WeatherSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(tripID: UUID, store: TripStore, weather: WeatherService) {
        self.tripID = tripID
        self.store = store
        self.weatherService = weather
    }

    var trip: Trip? { store.trip(tripID) }

    var updatedText: String {
        guard let snapshot else { return "" }
        switch snapshot.source {
        case .sample: return "Sample forecast • add an OpenWeatherMap API key for live weather"
        case .openWeatherMap: return "Updated \(snapshot.updatedAt) • OpenWeatherMap data"
        }
    }

    var offlineText: String? {
        guard let snapshot, snapshot.isOffline else { return nil }
        return "You're offline. Showing the forecast from \(snapshot.fetchedAt.text("EEE HH:mm"))."
    }

    var advisory: WeatherAdvisory? {
        guard let trip else { return nil }
        return WeatherAdvisor.headline(for: trip, snapshot: snapshot, now: store.now)
    }

    var activityAdvisories: [(activity: Activity, advisory: ActivityAdvisory)] {
        guard let trip else { return [] }
        return WeatherAdvisor.advisories(for: trip, snapshot: snapshot).compactMap { advisory in
            trip.activities.first { $0.id == advisory.activityID }.map { ($0, advisory) }
        }
    }

    func load(refresh: Bool = false) async {
        guard let trip, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await weatherService.forecast(for: trip, refresh: refresh)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
