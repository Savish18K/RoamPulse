import Foundation

// Pure functions so they're easy to test
enum ItineraryPlanner {

    // Same time sorted by title so the order doesn't jump
    static func ordered(_ activities: [Activity]) -> [Activity] {
        activities.sorted { ($0.minutes, $0.title) < ($1.minutes, $1.title) }
    }

    // The day keeps its time slots and gives them out in the new order
    static func reorder(_ dayActivities: [Activity], moving source: Int, to destination: Int) -> [Activity] {
        guard dayActivities.indices.contains(source),
              dayActivities.indices.contains(destination),
              source != destination else { return dayActivities }

        let slots = dayActivities.map(\.minutes).sorted()
        var reordered = dayActivities
        let moved = reordered.remove(at: source)
        reordered.insert(moved, at: destination)
        for index in reordered.indices {
            reordered[index].minutes = slots[index]
        }
        return reordered
    }

    // Keeps the time, day is clamped to the trip length
    static func move(_ activityID: UUID, toDay day: Int, dayCount: Int, in activities: [Activity]) -> [Activity] {
        let target = min(max(day, 1), max(dayCount, 1))
        return activities.map { activity in
            guard activity.id == activityID else { return activity }
            var moved = activity
            moved.day = target
            return moved
        }
    }

    static func replacing(_ changed: [Activity], in all: [Activity]) -> [Activity] {
        let changedByID = Dictionary(uniqueKeysWithValues: changed.map { ($0.id, $0) })
        return all.map { changedByID[$0.id] ?? $0 }
    }

    // Activities past the new last day move onto it
    static func clamp(_ activities: [Activity], toDayCount dayCount: Int) -> [Activity] {
        activities.map { activity in
            guard activity.day > dayCount else { return activity }
            var moved = activity
            moved.day = max(dayCount, 1)
            return moved
        }
    }

    static func clashes(day: Int, minutes: Int, ignoring id: UUID?, in activities: [Activity]) -> [Activity] {
        activities.filter { $0.day == day && $0.minutes == minutes && $0.id != id }
    }

    static func points(for effort: Effort) -> Int {
        switch effort {
        case .low: 1
        case .moderate: 2
        case .high: 4
        }
    }

    static let demandingPoints = 8
    static let moderatePoints = 5

    // low 1, moderate 2, high 4. 8+ is demanding, 5+ or any high is moderate
    static func intensity(of activities: [Activity]) -> DayIntensity? {
        guard !activities.isEmpty else { return nil }
        let total = activities.reduce(0) { $0 + points(for: $1.effort) }
        if total >= demandingPoints { return .demanding }
        if total >= moderatePoints || activities.contains(where: { $0.effort == .high }) { return .moderate }
        return .easy
    }

    static func demandingDayAdvice(today: DayIntensity?, previousDay: DayIntensity?) -> String? {
        guard today == .demanding else { return nil }
        if previousDay == .demanding {
            return "Second demanding day in a row. Think about moving something to a lighter day."
        }
        return "Start early, carry water and keep the evening light."
    }
}
