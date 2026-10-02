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
    let id = UUID()
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

struct WeatherAdvisory: Hashable {
    var day: Int
    var title: String
    var shortMessage: String
    var message: String
}

/// Saved forecast for a destination (mock until OpenWeatherMap is wired up).
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
    var updatedAt: String
    var hourly: [HourlyForecast]
    var daily: [DailyForecast]
    var advisory: WeatherAdvisory?
}
