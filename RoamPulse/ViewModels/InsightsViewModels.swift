import Foundation
import Observation

// Pure functions so they can be tested
enum MemorySearch {
    // Checks title, text, place, people, tags and landmark
    static func matches(_ memory: Memory, _ query: String) -> Bool {
        let text = query.trimmed
        guard !text.isEmpty else { return true }
        let fields = [memory.title, memory.transcript, memory.place, memory.landmark ?? ""]
            + memory.people.map(\.name) + memory.placeTags + memory.sceneTags
        return fields.contains { $0.localizedCaseInsensitiveContains(text) }
    }

    // Sentence containing the query, or the start of the text
    static func snippet(of text: String, matching query: String, maxLength: Int = 140) -> String {
        let sentences = text.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let index = sentences.firstIndex(where: { $0.localizedCaseInsensitiveContains(query.trimmed) }) else {
            return text.count > maxLength ? String(text.prefix(maxLength)) + "…" : text
        }
        return (index > 0 ? "… " : "") + sentences[index] + "."
    }

    // Most common places and people
    static func suggestions(from memories: [Memory], limit: Int = 6) -> [String] {
        var counts: [String: Int] = [:]
        for memory in memories {
            let terms = Set([memory.place] + memory.people.map(\.name) + (memory.landmark.map { [$0] } ?? []))
            for term in terms where !term.isEmpty {
                counts[term, default: 0] += 1
            }
        }
        // Ties sorted A-Z so the chips don't move around
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map(\.key)
    }

    // -1 to 1, from the sentiment or the mood picked by hand
    static func moodScore(_ memory: Memory) -> Double? {
        if let sentiment = memory.sentiment { return sentiment }
        switch memory.mood {
        case .positive: return 0.6
        case .mixed: return 0
        case .negative: return -0.6
        case nil: return nil
        }
    }
}

struct DayMood: Identifiable, Equatable {
    let date: Date
    let score: Double
    let count: Int

    var id: Date { date }
    var mood: Mood { score > 0.2 ? .positive : (score < -0.2 ? .negative : .mixed) }
}

struct TimelineDay: Identifiable, Equatable {
    let date: Date
    let title: String
    let memories: [Memory]

    var id: Date { date }
}

@MainActor
@Observable
final class InsightsViewModel {
    private let store: TripStore

    var query = ""
    // nil = all trips
    var tripFilter: UUID?

    init(store: TripStore) {
        self.store = store
    }

    var hasMemories: Bool { !store.memories.isEmpty }

    var memories: [Memory] {
        guard let tripFilter else { return store.sortedMemories }
        return store.memories(inTrip: tripFilter)
    }

    var tripsWithMemories: [Trip] {
        let ids = Set(store.memories.map(\.tripID))
        return store.trips.filter { ids.contains($0.id) }.sorted { $0.startDate > $1.startDate }
    }

    var results: [Memory] {
        guard !query.trimmed.isEmpty else { return [] }
        return memories.filter { MemorySearch.matches($0, query) }
    }

    var suggestions: [String] { MemorySearch.suggestions(from: memories) }

    func snippet(for memory: Memory) -> String {
        MemorySearch.snippet(of: memory.transcript, matching: query)
    }

    func tripName(for memory: Memory) -> String {
        store.trip(memory.tripID)?.name ?? ""
    }

    func isLatest(_ memory: Memory) -> Bool {
        memory.id == store.latestMemory?.id
    }

    var timeline: [TimelineDay] {
        let groups = Dictionary(grouping: memories) { Calendar.trip.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).compactMap { day in
            guard let dayMemories = groups[day]?.sorted(by: { $0.date < $1.date }), let first = dayMemories.first else {
                return nil
            }
            let trip = store.trip(first.tripID)?.name
            let title = "\(day.text("EEEE d MMM"))" + (trip.map { " • \($0), Day \(first.day)" } ?? "")
            return TimelineDay(date: day, title: title, memories: dayMemories)
        }
    }

    var dayMoods: [DayMood] {
        let scored = memories.compactMap { memory in MemorySearch.moodScore(memory).map { (memory, $0) } }
        let groups = Dictionary(grouping: scored) { Calendar.trip.startOfDay(for: $0.0.date) }
        return groups.map { date, items in
            DayMood(date: date, score: items.map(\.1).reduce(0, +) / Double(items.count), count: items.count)
        }
        .sorted { $0.date < $1.date }
    }

    func count(of mood: Mood) -> Int { memories.filter { $0.mood == mood }.count }

    var memoriesWithMood: [Memory] { memories.filter { $0.mood != nil } }
}

// Stats screen numbers, pure so they can be tested
struct TravelStats: Equatable {
    enum Period: Equatable {
        case year(Int)
        case allTime
    }

    struct TripSpending: Identifiable, Equatable {
        let id: UUID
        let name: String
        let byCategory: [ExpenseCategory: Double]
        var total: Double { byCategory.values.reduce(0, +) }
    }

    // Started trips only
    let trips: [Trip]
    let daysTravelled: Int
    let places: Int
    let memories: Int
    let photos: Int
    let totalSpent: Double
    // Only trips with a budget
    let budgetedSpent: Double
    let totalBudget: Double
    let byCategory: [ExpenseCategory: Double]
    let byTrip: [TripSpending]
    let landmarks: [String]

    var tripCount: Int { trips.count }
    var averagePerDay: Double { daysTravelled > 0 ? totalSpent / Double(daysTravelled) : 0 }
    var hasBudget: Bool { totalBudget > 0 }
    var isOnBudget: Bool { budgetedSpent <= totalBudget }
    var isEmpty: Bool { trips.isEmpty }

    static func make(trips allTrips: [Trip], memories allMemories: [Memory], now: Date, period: Period) -> TravelStats {
        let calendar = Calendar.trip
        let trips = allTrips
            .filter { $0.status(at: now) != .upcoming }
            .filter { trip in
                if case .year(let year) = period { return calendar.component(.year, from: trip.startDate) == year }
                return true
            }
            .sorted { $0.startDate < $1.startDate }
        let tripIDs = Set(trips.map(\.id))
        let memories = allMemories.filter { tripIDs.contains($0.tripID) }

        var byCategory: [ExpenseCategory: Double] = [:]
        let byTrip = trips.map { trip in
            var spending: [ExpenseCategory: Double] = [:]
            for category in ExpenseCategory.allCases {
                let amount = trip.spent(on: category)
                spending[category] = amount
                byCategory[category, default: 0] += amount
            }
            return TripSpending(id: trip.id, name: trip.name, byCategory: spending)
        }
        let budgeted = trips.filter { $0.budget > 0 }

        return TravelStats(
            trips: trips,
            // Active trip counts days so far
            daysTravelled: trips.reduce(0) { total, trip in
                total + (trip.status(at: now) == .active ? (trip.dayNumber(at: now) ?? 0) : trip.dayCount)
            },
            places: TripStore.placesVisited(in: trips),
            memories: memories.count,
            photos: memories.reduce(0) { $0 + $1.photos.count },
            totalSpent: trips.reduce(0) { $0 + $1.totalSpent },
            budgetedSpent: budgeted.reduce(0) { $0 + $1.totalSpent },
            totalBudget: budgeted.reduce(0) { $0 + $1.budget },
            byCategory: byCategory,
            byTrip: byTrip,
            landmarks: Set(memories.compactMap(\.landmark)).sorted()
        )
    }
}
