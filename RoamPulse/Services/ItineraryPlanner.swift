import Foundation

/// Rules for the day-by-day itinerary.
/// Everything here is a pure function (data in, data out), so it is easy to unit test.
enum ItineraryPlanner {

    /// Activities in time order. Activities at the same time are sorted by title,
    /// so the order never jumps around.
    static func ordered(_ activities: [Activity]) -> [Activity] {
        activities.sorted { ($0.minutes, $0.title) < ($1.minutes, $1.title) }
    }

    /// Drag to reorder within a day.
    ///
    /// The day keeps its time slots and hands them out in the new order, so the list is
    /// always in time order. e.g. dragging the 15:00 activity above the 06:00 one gives it
    /// 06:00 and pushes the others into the later slots.
    ///
    /// - Parameters:
    ///   - dayActivities: one day's activities, in the order they are shown.
    ///   - source: index of the activity being moved.
    ///   - destination: index the activity should end up at.
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

    /// Moves an activity to another day and keeps its time.
    /// The day is clamped to the trip, so it can't land on day 0 or after the last day.
    static func move(_ activityID: UUID, toDay day: Int, dayCount: Int, in activities: [Activity]) -> [Activity] {
        let target = min(max(day, 1), max(dayCount, 1))
        return activities.map { activity in
            guard activity.id == activityID else { return activity }
            var moved = activity
            moved.day = target
            return moved
        }
    }

    /// Puts changed activities back into the trip's full list, matching them by id.
    static func replacing(_ changed: [Activity], in all: [Activity]) -> [Activity] {
        let changedByID = Dictionary(uniqueKeysWithValues: changed.map { ($0.id, $0) })
        return all.map { changedByID[$0.id] ?? $0 }
    }

    /// When a trip is shortened, activities on days that no longer exist move to the new last day.
    static func clamp(_ activities: [Activity], toDayCount dayCount: Int) -> [Activity] {
        activities.map { activity in
            guard activity.day > dayCount else { return activity }
            var moved = activity
            moved.day = max(dayCount, 1)
            return moved
        }
    }

    /// Other activities on the same day at exactly the same time.
    static func clashes(day: Int, minutes: Int, ignoring id: UUID?, in activities: [Activity]) -> [Activity] {
        activities.filter { $0.day == day && $0.minutes == minutes && $0.id != id }
    }

    /// Effort points for one activity.
    static func points(for effort: Effort) -> Int {
        switch effort {
        case .low: 1
        case .moderate: 2
        case .high: 4
        }
    }

    /// A day with this many points or more is demanding.
    static let demandingPoints = 8
    /// A day with this many points or more (or any high-effort activity) is moderate.
    static let moderatePoints = 5

    /// Easy, moderate or demanding, worked out from the day's total effort points
    /// (low 1, moderate 2, high 4).
    ///
    /// - 8 points or more: demanding, e.g. a sunrise hike (4) + a waterfall walk (2) + two easy stops (1 + 1).
    /// - 5 points or more, or any high-effort activity: moderate.
    /// - Anything else: easy.
    ///
    /// Returns nil for a day with nothing planned.
    static func intensity(of activities: [Activity]) -> DayIntensity? {
        guard !activities.isEmpty else { return nil }
        let total = activities.reduce(0) { $0 + points(for: $1.effort) }
        if total >= demandingPoints { return .demanding }
        if total >= moderatePoints || activities.contains(where: { $0.effort == .high }) { return .moderate }
        return .easy
    }

    /// Advice shown under the badge on demanding days.
    /// Warns when two demanding days come back to back.
    static func demandingDayAdvice(today: DayIntensity?, previousDay: DayIntensity?) -> String? {
        guard today == .demanding else { return nil }
        if previousDay == .demanding {
            return "Second demanding day in a row. Think about moving something to a lighter day."
        }
        return "Start early, carry water and keep the evening light."
    }
}
