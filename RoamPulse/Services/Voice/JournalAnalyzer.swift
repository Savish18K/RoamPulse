import Foundation
import NaturalLanguage

struct TextAnalysis: Equatable {
    var places: [String] = []
    var people: [String] = []
    var organisations: [String] = []
    // -1 to 1, nil if nothing to score
    var sentiment: Double?

    var mood: Mood? { sentiment.map(JournalAnalyzer.mood) }
}

// Finds places, people and mood in the text using NLTagger (on device)
enum JournalAnalyzer {
    static let moodThreshold = 0.2

    // iOS downloads this the first time. Names and mood won't work until it's there
    @discardableResult
    static func prepareLanguageData(for language: NLLanguage = .english) async -> Bool {
        var available = true
        for scheme in [NLTagScheme.nameType, .sentimentScore] {
            let result: NLTagger.AssetsResult? = await withCheckedContinuation { continuation in
                NLTagger.requestAssets(for: language, tagScheme: scheme) { result, _ in
                    continuation.resume(returning: result)
                }
            }
            available = available && result == .available
        }
        return available
    }

    static func mood(for sentiment: Double) -> Mood {
        if sentiment > moodThreshold { return .positive }
        if sentiment < -moodThreshold { return .negative }
        return .mixed
    }

    static func analyse(_ text: String) -> TextAnalysis {
        var analysis = TextAnalysis()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return analysis }

        let tagger = NLTagger(tagSchemes: [.nameType, .sentimentScore])
        tagger.string = text

        // joinNames keeps "Nine Arch Bridge" as one name
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            let name = String(text[range])
            switch tag {
            case .placeName: append(name, to: &analysis.places)
            case .personalName: append(name, to: &analysis.people)
            case .organizationName: append(name, to: &analysis.organisations)
            default: break
            }
            return true
        }

        // Average per paragraph
        var scores: [Double] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .paragraph, scheme: .sentimentScore,
                             options: []) { tag, _ in
            if let value = tag.flatMap({ Double($0.rawValue) }) {
                scores.append(value)
            }
            return true
        }
        if !scores.isEmpty {
            analysis.sentiment = scores.reduce(0, +) / Double(scores.count)
        }
        return analysis
    }

    // Adds places, people, mood and the linked activity to the memory
    static func apply(_ analysis: TextAnalysis, text: String, to memory: inout Memory, trip: Trip) {
        let members = membersMentioned(in: text, analysis: analysis, members: trip.members)
        let memberNames = Set(trip.members.map { $0.name.lowercased() })

        var places: [String] = []
        for place in analysis.places + knownPlacesMentioned(in: text, trip: trip)
            where !memberNames.contains(place.lowercased()) {
            append(place, to: &places)
        }
        if !places.isEmpty {
            memory.placeTags = places
        }

        for member in members where !memory.people.contains(where: { $0.id == member.id }) {
            memory.people.append(member)
        }

        // Mood was picked by hand, keep it
        let moodPickedByHand = memory.mood != nil && memory.sentiment == nil
        if !moodPickedByHand {
            memory.sentiment = analysis.sentiment
            memory.mood = analysis.mood
        }

        if memory.linkedActivity == nil,
           let activity = activityMentioned(in: text, places: places, trip: trip, day: memory.day, near: memory.date) {
            memory.linkedActivity = "Day \(activity.day) • \(activity.timeText) \(activity.title)"
        }
    }

    // Whole word match so "Suu" doesn't match "Suun"
    static func membersMentioned(in text: String, analysis: TextAnalysis, members: [Member]) -> [Member] {
        members.filter { member in
            guard !member.isMe else { return false }
            let first = member.name.components(separatedBy: " ").first ?? member.name
            return containsWord(first, in: text)
                || analysis.people.contains { $0.localizedCaseInsensitiveCompare(member.name) == .orderedSame }
        }
    }

    static func knownPlacesMentioned(in text: String, trip: Trip) -> [String] {
        let destinationParts = trip.destination.components(separatedBy: " to ")
        let candidates = trip.activities.map(\.place) + destinationParts
        return candidates
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && containsWord($0, in: text) }
    }

    // Title match first, otherwise the closest activity at a mentioned place
    static func activityMentioned(in text: String, places: [String], trip: Trip, day: Int, near date: Date) -> Activity? {
        let activities = trip.activities(onDay: day)
        if let byTitle = activities.first(where: { containsWord($0.title, in: text) }) {
            return byTitle
        }
        let placeNames = Set(places.map { $0.lowercased() })
        let atPlace = activities.filter { !$0.place.isEmpty && placeNames.contains($0.place.lowercased()) }
        let minutes = Calendar.trip.minutesSinceMidnight(date)
        return atPlace.min { abs($0.minutes - minutes) < abs($1.minutes - minutes) }
    }

    // Whole word, ignores case
    static func containsWord(_ word: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return text.range(of: "\\b\(escaped)\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func append(_ name: String, to list: inout [String]) {
        if !list.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            list.append(name)
        }
    }
}
