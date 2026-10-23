import Foundation

/// Live weather from OpenWeatherMap, saved per trip so it still shows offline.
///
/// 1. A forecast saved less than 15 minutes ago is used as it is (no download).
/// 2. Otherwise the trip's coordinates are used (or looked up once from its destination and saved
///    on the trip), and the current weather and 5-day forecast are downloaded together.
/// 3. The download is saved in Core Data (`ForecastCacheEntity`) with the time it was fetched.
/// 4. With no connection, the saved forecast is shown with an "offline" banner.
@MainActor
final class OpenWeatherMapService: WeatherService {
    /// How long a download is reused before asking again. The free plan allows 60 calls a minute.
    static let freshFor: TimeInterval = 15 * 60

    private let client: OpenWeatherMapClient
    private let clock: Clock
    /// Where forecasts are cached and looked-up coordinates are saved. Set by `AppDependencies`.
    weak var store: TripStore?
    /// Called after a new forecast is downloaded, so weather alerts can be sent.
    var onNewForecast: ((Trip, WeatherSnapshot) -> Void)?

    /// Home, Trips and the trip screen often ask for the same trip at once; they share one download.
    private var inFlight: [UUID: Task<WeatherSnapshot, Error>] = [:]

    init(client: OpenWeatherMapClient, clock: Clock) {
        self.client = client
        self.clock = clock
    }

    func forecast(for trip: Trip, refresh: Bool) async throws -> WeatherSnapshot {
        if let running = inFlight[trip.id] {
            return try await running.value
        }
        let task = Task { try await self.load(trip, refresh: refresh) }
        inFlight[trip.id] = task
        defer { inFlight[trip.id] = nil }
        return try await task.value
    }

    func searchPlaces(_ query: String) async throws -> [Place] {
        let places = try await client.searchPlaces(query)
        // The same town can come back twice (once per language); keep one of each.
        var seen = Set<String>()
        return places.compactMap { place in
            let region = [place.state, place.country].compactMap { $0 }.joined(separator: ", ")
            guard seen.insert("\(place.name)|\(region)").inserted else { return nil }
            return Place(name: place.name, region: region, latitude: place.lat, longitude: place.lon)
        }
    }

    // MARK: - Loading

    private func load(_ trip: Trip, refresh: Bool) async throws -> WeatherSnapshot {
        let cached = store?.cachedForecast(for: trip.id)
        let cachedBundle = cached.flatMap { try? OpenWeatherMapClient.decoder.decode(OpenWeatherMapBundle.self, from: $0.payload) }
        let isForThisPlace = trip.hasCoordinates && cached?.location == Self.locationKey(for: trip)

        if !refresh, let cached, let cachedBundle, isForThisPlace,
           clock.now.timeIntervalSince(cached.fetchedAt) < Self.freshFor {
            return ForecastBuilder.snapshot(from: cachedBundle, for: trip, now: clock.now,
                                            fetchedAt: cached.fetchedAt, isOffline: false)
        }

        do {
            let located = try await withCoordinates(trip)
            guard let latitude = located.latitude, let longitude = located.longitude else {
                throw WeatherError.placeNotFound(trip.mainPlace)
            }
            async let current = client.current(latitude: latitude, longitude: longitude)
            async let forecast = client.forecast(latitude: latitude, longitude: longitude)
            let bundle = OpenWeatherMapBundle(placeName: trip.mainPlace, current: try await current,
                                              forecast: try await forecast)
            let now = clock.now
            if let payload = try? OpenWeatherMapClient.encoder.encode(bundle) {
                store?.saveForecast(CachedForecast(payload: payload, location: Self.locationKey(for: located),
                                                   fetchedAt: now), for: trip.id)
            }
            let snapshot = ForecastBuilder.snapshot(from: bundle, for: located, now: now, fetchedAt: now, isOffline: false)
            onNewForecast?(located, snapshot)
            return snapshot
        } catch let error where WeatherError.isConnectionProblem(error) {
            // Offline: show the last forecast for this trip, if there is one.
            guard let cached, let cachedBundle else { throw WeatherError.offline }
            return ForecastBuilder.snapshot(from: cachedBundle, for: trip, now: clock.now,
                                            fetchedAt: cached.fetchedAt, isOffline: true)
        }
    }

    /// The trip with coordinates. Trips whose destination was typed (not picked from the suggestions)
    /// are looked up once, preferring a Sri Lankan match, and the result is saved on the trip.
    private func withCoordinates(_ trip: Trip) async throws -> Trip {
        guard !trip.hasCoordinates else { return trip }
        let matches = try await client.searchPlaces(trip.mainPlace)
        guard let place = Self.bestMatch(in: matches) else { throw WeatherError.placeNotFound(trip.mainPlace) }
        var located = trip
        located.latitude = place.lat
        located.longitude = place.lon
        store?.updateTrip(trip.id) { saved in
            saved.latitude = place.lat
            saved.longitude = place.lon
        }
        return located
    }

    /// The app is for travel in Sri Lanka, so "Ella" means Ella, LK rather than a town abroad.
    static func bestMatch(in places: [OWMPlace]) -> OWMPlace? {
        places.first { $0.country == "LK" } ?? places.first
    }

    /// Which place a cached forecast is for, rounded so tiny coordinate changes don't matter.
    static func locationKey(for trip: Trip) -> String {
        guard let latitude = trip.latitude, let longitude = trip.longitude else { return "" }
        return String(format: "%.3f,%.3f", latitude, longitude)
    }
}
