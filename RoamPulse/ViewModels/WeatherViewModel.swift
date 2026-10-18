import Foundation
import Observation

/// Weather screen for one trip. The forecast comes from the injected `WeatherService`
/// (sample data now, OpenWeatherMap from Increment 7).
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
        return "Updated \(snapshot.updatedAt) • OpenWeatherMap data"
    }

    func load() async {
        guard let trip, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await weatherService.forecast(for: trip)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the forecast. \(error.localizedDescription)"
        }
    }
}
