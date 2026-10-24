import SwiftUI

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

    // Icon too so mood isn't shown by colour only
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

// Sample photo or one the user picked (stored in Core Data, not uploaded)
enum MemoryPhoto: Hashable {
    case sample(SamplePhoto)
    case stored(UUID)

    var key: String {
        switch self {
        case .sample(let photo): "sample-\(photo.rawValue)"
        case .stored(let id): "stored-\(id.uuidString)"
        }
    }

    var storedImageID: UUID? {
        if case .stored(let id) = self { id } else { nil }
    }
}

struct Memory: Identifiable, Hashable {
    var id = UUID()
    var tripID: UUID
    var title: String
    var date: Date
    var day: Int
    var place: String
    var transcript: String
    // Seconds, 0 for photo-only memories
    var duration: Int
    var people: [Member]
    var mood: Mood?
    var sentiment: Double?
    var placeTags: [String] = []
    var landmark: String?
    var landmarkConfidence: Double?
    var sceneTags: [String] = []
    var photos: [MemoryPhoto] = []
    var linkedActivity: String?
    var isVisited = false
    // Speech recognition doesn't support the language
    var transcriptUnavailable = false
    // File name in the Recordings folder, sample memories don't have one
    var audioFileName: String?

    var hasVoice: Bool { duration > 0 }

    var peopleText: String { people.map(\.name).joined(separator: ", ") }

    var hasText: Bool { !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var kindText: String {
        switch (photos.isEmpty, hasVoice) {
        case (false, true): "Photo + voice"
        case (false, false): "Photo"
        case (true, true): "Voice"
        case (true, false): "Note"
        }
    }

    var storedImageIDs: [UUID] { photos.compactMap(\.storedImageID) }
}

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

struct LandmarkCandidate: Identifiable, Hashable {
    var name: String
    var confidence: Double

    var id: String { name }
}

// Fake model output for now
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

struct WeatherAdvisory: Hashable {
    var day: Int
    var title: String
    var shortMessage: String
    var message: String
}

struct ActivityAdvisory: Hashable {
    enum Kind: Hashable {
        case storm, rain, heat
    }

    var activityID: UUID
    var day: Int
    var kind: Kind
    // e.g. "Heavy rain likely"
    var title: String
    // e.g. "14:00–17:00"
    var window: String
    // So the alert is only sent once
    var windowStart: Date
    var message: String

    var icon: String {
        switch kind {
        case .storm: "cloud.bolt.rain.fill"
        case .rain: "cloud.heavyrain.fill"
        case .heat: "thermometer.sun.fill"
        }
    }
}

// One 3 hour step from OpenWeatherMap
struct ForecastSlot: Hashable {
    static let length: TimeInterval = 3 * 60 * 60

    var start: Date
    var temperature: Int
    // 0-100
    var rainChance: Int
    var rainMM: Double
    // 2xx storm, 3xx drizzle, 5xx rain, 800 clear, 80x clouds
    var conditionCode: Int
    var condition: String
    var symbol: String

    var end: Date { start.addingTimeInterval(Self.length) }
    var isStormy: Bool { (200..<300).contains(conditionCode) }
}

enum WeatherSource: Hashable {
    case openWeatherMap
    // Used when there's no API key
    case sample
}

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
    var fetchedAt: Date
    var hourly: [HourlyForecast]
    var daily: [DailyForecast]
    var slots: [ForecastSlot]
    // No connection, showing the saved forecast
    var isOffline = false
    var source: WeatherSource = .openWeatherMap

    var updatedAt: String { fetchedAt.text("HH:mm") }
}

// For Settings -> Export my data
extension Memory: Encodable {}
extension MemoryPhoto: Encodable {}
extension Mood: Encodable {}
