import Foundation
import NaturalLanguage

/// What the Natural Language framework found in a memory's text.
struct TextAnalysis: Equatable {
    /// Place names, e.g. "Ella", "Nine Arch Bridge".
    var places: [String] = []
    /// People's names.
    var people: [String] = []
    /// Organisations, e.g. "Sri Lanka Railways".
    var organisations: [String] = []
    /// -1 (negative) … 1 (positive), or nil if there was nothing to score.
    var sentiment: Double?

    var mood: Mood? { sentiment.map(JournalAnalyzer.mood) }
}

/// Reads a memory's text on the iPhone with the Natural Language framework (no server):
/// the places, people and organisations mentioned (`NLTagger` name types) and how it feels
/// (`NLTagger` sentiment score). `apply` then links what was found to the trip: its members,
/// its places and the activity the memory is about.
enum JournalAnalyzer {
    /// Sentiment above this reads as positive, below the negative of it as negative.
    static let moodThreshold = 0.2

    /// Makes sure the on-device language data for names and sentiment is installed (iOS downloads it
    /// once, in the background, when first needed). Returns false if it isn't available, in which case
    /// `analyse` still links trip members and places by name but can't read names or mood.
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

        // Named entities. joinNames keeps "Nine Arch Bridge" together instead of three words.
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

        // Sentiment per paragraph, averaged (one long memory can have a good and a bad part).
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

    /// Updates the memory with what the text says:
    /// - place tags: places found by the tagger plus the trip's own places mentioned by name;
    /// - people: trip members mentioned by name are added (people already tagged stay);
    /// - mood: read from the sentiment, unless the user picked a mood by hand;
    /// - linked activity: the activity that day whose name or place is mentioned, if none is linked yet.
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

        // A mood with no sentiment was picked by hand: keep it.
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

    /// Trip members named in the text. Names are matched as whole words, so "Suu" doesn't match "Suun".
    static func membersMentioned(in text: String, analysis: TextAnalysis, members: [Member]) -> [Member] {
        members.filter { member in
            guard !member.isMe else { return false }
            let first = member.name.components(separatedBy: " ").first ?? member.name
            return containsWord(first, in: text)
                || analysis.people.contains { $0.localizedCaseInsensitiveCompare(member.name) == .orderedSame }
        }
    }

    /// The trip's places (activity places, the destination) that the text names.
    static func knownPlacesMentioned(in text: String, trip: Trip) -> [String] {
        let destinationParts = trip.destination.components(separatedBy: " to ")
        let candidates = trip.activities.map(\.place) + destinationParts
        return candidates
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && containsWord($0, in: text) }
    }

    /// The activity on `day` the memory is about: one whose title is in the text first, otherwise
    /// one at a place that was mentioned (the closest in time to the memory, if several).
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

    /// Case-insensitive whole-word match: "Ella" is found in "Ella's" and "in Ella." but not in "Bellagio".
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
