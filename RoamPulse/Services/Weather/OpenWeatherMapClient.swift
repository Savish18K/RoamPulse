import Foundation

// OpenWeatherMap free API: geocoding, current weather and 5 day forecast

enum OpenWeatherMapConfig {
    // nil if the key hasn't been added, sample weather is used then
    static var apiKey: String? {
        guard let url = Bundle.main.url(forResource: "OpenWeatherMap", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url),
              let key = (values["API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty, !key.hasPrefix("PASTE") else { return nil }
        return key
    }
}

enum WeatherError: LocalizedError, Equatable {
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

    static func isConnectionProblem(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff].contains(error.code)
    }
}

// Protocol so tests can return saved JSON
protocol HTTPClient {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    var session: URLSession = .shared

    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await session.data(from: url)
    }
}

// Only the fields we use

struct OWMCondition: Codable, Hashable {
    // e.g. 500 = light rain
    var id: Int
    var main: String
    var description: String
    // "10d" or "10n"
    var icon: String
}

// GET /data/2.5/weather
struct OWMCurrent: Codable, Hashable {
    struct Main: Codable, Hashable {
        var temp: Double
        var tempMin: Double
        var tempMax: Double
        var humidity: Int
    }

    struct Wind: Codable, Hashable {
        // m/s
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

// GET /data/2.5/forecast (40 x 3 hours)
struct OWMForecast: Codable, Hashable {
    struct Item: Codable, Hashable {
        struct Main: Codable, Hashable {
            var temp: Double
            var humidity: Int
        }

        // JSON key is "3h"
        struct Volume: Codable, Hashable {
            var threeHours: Double?

            enum CodingKeys: String, CodingKey {
                case threeHours = "3h"
            }
        }

        var dt: TimeInterval
        var main: Main
        var weather: [OWMCondition]
        // 0 to 1
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

// GET /geo/1.0/direct
struct OWMPlace: Codable, Hashable {
    var name: String
    var lat: Double
    var lon: Double
    var country: String
    var state: String?
}

// Saved together in the cache
struct OpenWeatherMapBundle: Codable, Hashable {
    var placeName: String
    var current: OWMCurrent
    var forecast: OWMForecast
}

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
