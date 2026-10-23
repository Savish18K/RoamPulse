import Foundation

// The OpenWeatherMap REST API (free plan): geocoding, current weather and the 5 day / 3 hour forecast.
// https://openweathermap.org/api

// MARK: - Configuration

enum OpenWeatherMapConfig {
    /// The API key from OpenWeatherMap.plist (key `API_KEY`), or nil if it hasn't been filled in.
    /// Without a key the app shows sample weather instead.
    static var apiKey: String? {
        guard let url = Bundle.main.url(forResource: "OpenWeatherMap", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url),
              let key = (values["API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty, !key.hasPrefix("PASTE") else { return nil }
        return key
    }
}

// MARK: - Errors

enum WeatherError: LocalizedError, Equatable {
    /// No connection, and no saved forecast to show instead.
    case offline
    case invalidAPIKey
    case tooManyRequests
    case placeNotFound(String)
    case server(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .offline: "You're offline and there's no saved forecast for this trip yet."
        case .invalidAPIKey: "OpenWeatherMap didn't accept the API key. New keys can take up to 2 hours to start working."
        case .tooManyRequests: "Too many weather requests. Try again in a minute."
        case .placeNotFound(let place): "Couldn't find “\(place)” on the map. Edit the trip's destination and try again."
        case .server(let code): "The weather service had a problem (error \(code)). Try again later."
        case .badResponse: "The weather service sent something unexpected."
        }
    }

    /// Network errors that mean "no connection" rather than a real failure.
    static func isConnectionProblem(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff].contains(error.code)
    }
}

// MARK: - HTTP

/// The one network call the client makes, behind a protocol so tests can return saved JSON.
protocol HTTPClient {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    var session: URLSession = .shared

    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await session.data(from: url)
    }
}

// MARK: - Responses

// Only the fields the app uses. Snake-case JSON keys (temp_min) are converted to camelCase.

struct OWMCondition: Codable, Hashable {
    /// e.g. 500 (light rain). See https://openweathermap.org/weather-conditions
    var id: Int
    var main: String
    var description: String
    /// e.g. "10d" (day) or "10n" (night).
    var icon: String
}

/// `GET /data/2.5/weather`
struct OWMCurrent: Codable, Hashable {
    struct Main: Codable, Hashable {
        var temp: Double
        var tempMin: Double
        var tempMax: Double
        var humidity: Int
    }

    struct Wind: Codable, Hashable {
        /// Metres per second.
        var speed: Double
    }

    struct Sys: Codable, Hashable {
        var sunrise: TimeInterval?
        var sunset: TimeInterval?
    }

    var weather: [OWMCondition]
    var main: Main
    var wind: Wind
    var sys: Sys
    var name: String
    var dt: TimeInterval
}

/// `GET /data/2.5/forecast`: 40 steps of 3 hours.
struct OWMForecast: Codable, Hashable {
    struct Item: Codable, Hashable {
        struct Main: Codable, Hashable {
            var temp: Double
            var humidity: Int
        }

        /// Rain or snow in the last 3 hours, in mm. The JSON key is "3h".
        struct Volume: Codable, Hashable {
            var threeHours: Double?

            enum CodingKeys: String, CodingKey {
                case threeHours = "3h"
            }
        }

        var dt: TimeInterval
        var main: Main
        var weather: [OWMCondition]
        /// Probability of precipitation, 0…1.
        var pop: Double?
        var rain: Volume?
        var snow: Volume?
    }

    struct City: Codable, Hashable {
        var name: String
    }

    var list: [Item]
    var city: City
}

/// `GET /geo/1.0/direct`: places matching a name.
struct OWMPlace: Codable, Hashable {
    var name: String
    var lat: Double
    var lon: Double
    var country: String
    var state: String?
}

/// Both downloads for a trip, saved together in the forecast cache.
struct OpenWeatherMapBundle: Codable, Hashable {
    var placeName: String
    var current: OWMCurrent
    var forecast: OWMForecast
}

// MARK: - Client

struct OpenWeatherMapClient {
    let apiKey: String
    var http: HTTPClient = URLSessionHTTPClient()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    func searchPlaces(_ query: String, limit: Int = 5) async throws -> [OWMPlace] {
        try await get("/geo/1.0/direct", [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "\(limit)")])
    }

    func current(latitude: Double, longitude: Double) async throws -> OWMCurrent {
        try await get("/data/2.5/weather", coordinates(latitude, longitude))
    }

    func forecast(latitude: Double, longitude: Double) async throws -> OWMForecast {
        try await get("/data/2.5/forecast", coordinates(latitude, longitude))
    }

    private func coordinates(_ latitude: Double, _ longitude: Double) -> [URLQueryItem] {
        [URLQueryItem(name: "lat", value: "\(latitude)"),
         URLQueryItem(name: "lon", value: "\(longitude)"),
         URLQueryItem(name: "units", value: "metric")]
    }

    private func get<Response: Decodable>(_ path: String, _ query: [URLQueryItem]) async throws -> Response {
        var components = URLComponents(string: "https://api.openweathermap.org")
        components?.path = path
        components?.queryItems = query + [URLQueryItem(name: "appid", value: apiKey)]
        guard let url = components?.url else { throw WeatherError.badResponse }

        let (data, response) = try await http.data(from: url)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw WeatherError.badResponse }
        switch status {
        case 200:
            do {
                return try Self.decoder.decode(Response.self, from: data)
            } catch {
                throw WeatherError.badResponse
            }
        case 401: throw WeatherError.invalidAPIKey
        case 429: throw WeatherError.tooManyRequests
        default: throw WeatherError.server(status)
        }
    }
}
