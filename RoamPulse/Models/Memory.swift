import SwiftUI

// MARK: - Memory

enum Mood: String, CaseIterable, Identifiable {
    case positive = "Positive"
    case mixed = "Mixed"
    case negative = "Negative"

    var id: Self { self }

    var color: Color {
        switch self {
        case .positive: .green
        case .mixed: .gray
        case .negative: .red
        }
    }

    /// Weather-style icon so mood never relies on colour alone.
    var icon: String {
        switch self {
        case .positive: "sun.max.fill"
        case .mixed: "cloud.sun.fill"
        case .negative: "cloud.rain.fill"
        }
    }

    var summary: String {
        switch self {
        case .positive: "The tone of this memory suggests excitement and joy."
        case .mixed: "This memory has a mix of good and not-so-good moments."
        case .negative: "The tone of this memory suggests a difficult moment."
        }
    }
}

/// A journal entry: a voice recording, photos, or both.
struct Memory: Identifiable, Hashable {
    var id = UUID()
    var tripID: UUID
    var title: String
    var date: Date
    var day: Int
    var place: String
    var transcript: String
    /// Recording length in seconds. 0 = photo-only memory.
    var duration: Int
    var people: [Member]
    var mood: Mood?
    var sentiment: Double?
    var placeTags: [String] = []
    var landmark: String?
    var landmarkConfidence: Double?
    var sceneTags: [String] = []
    var photos: [SamplePhoto] = []
    var linkedActivity: String?
    var isVisited = false
    /// True when on-device speech recognition doesn't support the language.
    var transcriptUnavailable = false

    var hasVoice: Bool { duration > 0 }

    var peopleText: String { people.map(\.name).joined(separator: ", ") }

    /// "Photo + voice", "Photo" or "Voice"
    var kindText: String {
        switch (photos.isEmpty, hasVoice) {
        case (false, true): "Photo + voice"
        case (false, false): "Photo"
        default: "Voice"
        }
    }
}

// MARK: - Landmark

enum LandmarkCategory: String, CaseIterable, Identifiable {
    case bridge = "Bridge"
    case temple = "Temple"
    case mountain = "Mountain"
    case beach = "Beach"
    case city = "City"

    var id: Self { self }
}

enum LandmarkStatus: Hashable {
    case recognised(confidence: Double)
    case confirmedByUser
    case voiceOnly
    case planned(trip: String)
    case notVisited
}

/// One of the Sri Lankan landmarks the Core ML model will recognise.
struct Landmark: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var location: String
    var category: LandmarkCategory
    var photo: SamplePhoto
    var status: LandmarkStatus
    var tripName: String?
    var photoCount = 0
    var voiceCount = 0

    /// Recognised in a photo (automatically or confirmed by the user).
    var isFound: Bool {
        switch status {
        case .recognised, .confirmedByUser: true
        default: false
        }
    }

    var confidence: Double? {
        if case .recognised(let confidence) = status { return confidence }
        return nil
    }
}

/// One guess from the landmark model.
struct LandmarkCandidate: Identifiable, Hashable {
    var name: String
    var confidence: Double

    var id: String { name }
}

/// Mock output of the landmark model + Vision scene tags for a photo.
struct RecognitionResult: Hashable {
    static let threshold = 0.7
    static let otherLabel = "Other (not a landmark)"

    var candidates: [LandmarkCandidate]
    var sceneTags: [String]

    var top: LandmarkCandidate? { candidates.first }

    var isConfident: Bool {
        guard let top else { return false }
        return top.confidence >= Self.threshold && top.name != Self.otherLabel
    }
}

// MARK: - Weather

struct HourlyForecast: Identifiable, Hashable {
    let id = UUID()
    var label: String
    var temperature: Int
    var rainChance: Int
    var symbol: String
}

struct DailyForecast: Identifiable, Hashable {
    let id = UUID()
    var dayLabel: String
    var tripDay: Int?
    var condition: String
    var symbol: String
    var rainChance: Int?
    var high: Int
    var low: Int
}

/// The headline warning shown on Home and the Weather screen, for the next outdoor activity at risk.
struct WeatherAdvisory: Hashable {
    var day: Int
    var title: String
    var shortMessage: String
    var message: String
}

/// A warning for one outdoor activity, worked out by `WeatherAdvisor`.
struct ActivityAdvisory: Hashable {
    enum Kind: Hashable {
        case storm, rain, heat
    }

    var activityID: UUID
    var day: Int
    var kind: Kind
    /// e.g. "Heavy rain likely"
    var title: String
    /// e.g. "14:00–17:00"
    var window: String
    /// When the risky weather starts, used to send the alert only once.
    var windowStart: Date
    /// e.g. "Heavy rain likely 14:00–17:00 (90%). Drier around 08:00 (20%)."
    var message: String

    var icon: String {
        switch kind {
        case .storm: "cloud.bolt.rain.fill"
        case .rain: "cloud.heavyrain.fill"
        case .heat: "thermometer.sun.fill"
        }
    }
}

/// One 3-hour step of the forecast (OpenWeatherMap's 5 day / 3 hour forecast).
struct ForecastSlot: Hashable {
    static let length: TimeInterval = 3 * 60 * 60

    var start: Date
    var temperature: Int
    /// Chance of rain or snow, 0–100.
    var rainChance: Int
    /// Rain (and snow) expected during the 3 hours, in mm.
    var rainMM: Double
    /// OpenWeatherMap's condition code: 2xx thunderstorm, 3xx drizzle, 5xx rain, 800 clear, 80x clouds.
    var conditionCode: Int
    var condition: String
    var symbol: String

    var end: Date { start.addingTimeInterval(Self.length) }
    var isStormy: Bool { (200..<300).contains(conditionCode) }
}

enum WeatherSource: Hashable {
    case openWeatherMap
    /// Built-in sample data, used when no OpenWeatherMap API key is set (and in previews).
    case sample
}

/// Forecast for a trip's destination.
struct WeatherSnapshot: Hashable {
    var location: String
    var condition: String
    var symbol: String
    var temperature: Int
    var high: Int
    var low: Int
    var humidity: Int
    var windKmh: Int
    var rainChance: Int
    var sunset: String
    /// When the forecast was downloaded.
    var fetchedAt: Date
    var hourly: [HourlyForecast]
    var daily: [DailyForecast]
    /// Every 3-hour step, used for the advice on each activity.
    var slots: [ForecastSlot]
    /// True when there was no connection and a saved forecast is shown.
    var isOffline = false
    var source: WeatherSource = .openWeatherMap

    /// "16:32"
    var updatedAt: String { fetchedAt.text("HH:mm") }
}

// Encodable for Settings → Export my data.
extension Memory: Encodable {}
extension Mood: Encodable {}
