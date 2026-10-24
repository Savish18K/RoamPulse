import Foundation
import Observation

@MainActor
@Observable
final class TripDetailViewModel {
    let tripID: UUID
    private let store: TripStore
    private let clock: Clock
    private let weatherService: WeatherService

    // Starts at 1
    var selectedDay: Int
    var showDeleteConfirmation = false
    private(set) var weather: WeatherSnapshot?

    init(tripID: UUID, initialDay: Int? = nil, store: TripStore, clock: Clock, weather: WeatherService) {
        self.tripID = tripID
        self.store = store
        self.clock = clock
        self.weatherService = weather
        // Requested day, else today, else day 1
        selectedDay = initialDay ?? store.trip(tripID)?.dayNumber(at: clock.now) ?? 1
    }

    var trip: Trip? { store.trip(tripID) }

    var now: Date { clock.now }

    func statusText(for trip: Trip) -> String { trip.statusText(at: now) }

    func subtitle(for trip: Trip) -> String {
        "\(trip.destination) • \(trip.dateRangeText) \(trip.endDate.text("yyyy"))"
    }

    func packingText(for trip: Trip) -> String { "\(trip.packedCount) / \(trip.packing.count) items" }

    func budgetText(for trip: Trip) -> String {
        trip.budget > 0 ? "\(trip.budgetLeft.lkr) left" : "\(trip.totalSpent.lkr) spent"
    }

    func weatherText(for trip: Trip) -> String {
        if trip.status(at: now) == .completed { return "Trip ended" }
        guard let weather else { return "Loading…" }
        return "\(weather.temperature)° • \(weather.condition)"
    }

    func memoriesText(for trip: Trip) -> String {
        let count = store.memories(inTrip: trip.id).count
        return "\(count) \(count == 1 ? "memory" : "memories")"
    }

    var dayTitles: [String] { (1...(trip?.dayCount ?? 1)).map { "Day \($0)" } }

    // Segmented control uses 0-based
    var selectedDayIndex: Int {
        get { selectedDay - 1 }
        set { selectedDay = newValue + 1 }
    }

    // Days with a weather warning get an orange dot
    var advisoryDayIndexes: Set<Int> {
        guard let trip else { return [] }
        return Set(WeatherAdvisor.advisoryDays(for: trip, in: weather).map { $0 - 1 })
    }

    var activities: [Activity] { trip?.activities(onDay: selectedDay) ?? [] }

    var selectedDateText: String { trip?.date(ofDay: selectedDay).text("EEE d MMM") ?? "" }

    var isToday: Bool { trip?.dayNumber(at: now) == selectedDay }

    var nextActivity: Activity? { isToday ? trip?.nextActivity(at: now) : nil }

    var nowText: String { "NOW • \(now.text("HH:mm"))" }

    var intensity: DayIntensity? { trip?.intensity(ofDay: selectedDay) }

    var intensityAdvice: String? {
        let previous = selectedDay > 1 ? trip?.intensity(ofDay: selectedDay - 1) : nil
        return ItineraryPlanner.demandingDayAdvice(today: intensity, previousDay: previous)
    }

    func advisory(for activity: Activity) -> ActivityAdvisory? {
        guard let trip else { return nil }
        return WeatherAdvisor.advisory(for: activity, in: trip, snapshot: weather)
    }

    func statusText(for activity: Activity) -> String {
        if activity.isDone { return "\(activity.timeText) • Done" }
        if activity.id == nextActivity?.id { return "\(activity.timeText) • Up next" }
        return activity.timeText
    }

    func otherDays(for activity: Activity) -> [Int] {
        (1...(trip?.dayCount ?? 1)).filter { $0 != activity.day }
    }

    func canMoveUp(_ activity: Activity) -> Bool { activities.first?.id != activity.id }

    func canMoveDown(_ activity: Activity) -> Bool { activities.last?.id != activity.id }

    func toggleDone(_ activity: Activity) {
        store.updateTrip(tripID) { trip in
            guard let index = trip.activities.firstIndex(where: { $0.id == activity.id }) else { return }
            trip.activities[index].isDone.toggle()
        }
    }

    func delete(_ activity: Activity) {
        store.updateTrip(tripID) { trip in
            trip.activities.removeAll { $0.id == activity.id }
        }
    }

    // Keeps its time
    func move(_ activity: Activity, toDay day: Int) {
        store.updateTrip(tripID) { trip in
            trip.activities = ItineraryPlanner.move(activity.id, toDay: day, dayCount: trip.dayCount, in: trip.activities)
        }
    }

    // false if it isn't an activity from this day
    @discardableResult
    func moveActivity(_ draggedID: UUID, onto target: Activity) -> Bool {
        let day = activities
        guard let source = day.firstIndex(where: { $0.id == draggedID }),
              let destination = day.firstIndex(where: { $0.id == target.id }) else { return false }
        reorder(day, from: source, to: destination)
        return true
    }

    // Dropping on a day tab moves it there
    @discardableResult
    func moveActivity(_ draggedID: UUID, toDayIndex index: Int) -> Bool {
        guard let activity = trip?.activities.first(where: { $0.id == draggedID }), activity.day != index + 1 else {
            return false
        }
        move(activity, toDay: index + 1)
        return true
    }

    // For VoiceOver since you can't drag
    func moveUp(_ activity: Activity) {
        guard let index = activities.firstIndex(where: { $0.id == activity.id }), index > 0 else { return }
        reorder(activities, from: index, to: index - 1)
    }

    func moveDown(_ activity: Activity) {
        guard let index = activities.firstIndex(where: { $0.id == activity.id }), index < activities.count - 1 else { return }
        reorder(activities, from: index, to: index + 1)
    }

    private func reorder(_ day: [Activity], from source: Int, to destination: Int) {
        let reordered = ItineraryPlanner.reorder(day, moving: source, to: destination)
        store.updateTrip(tripID) { trip in
            trip.activities = ItineraryPlanner.replacing(reordered, in: trip.activities)
        }
    }

    // true when it's gone so the screen can close
    func deleteTrip() -> Bool {
        store.deleteTrip(tripID)
    }

    // Shared members can only leave
    var canDeleteForEveryone: Bool { trip.map(store.isOwner) ?? true }

    // Needs an account
    var canShare: Bool { store.accountID != nil }

    var deleteTitle: String { canDeleteForEveryone ? "Delete Trip" : "Leave Trip" }

    func deleteMessage(for trip: Trip) -> String {
        if !canDeleteForEveryone {
            return "\(trip.name) will be removed from this iPhone. It stays for the rest of the group."
        }
        if trip.isShared {
            return "It will be deleted for everyone on the trip. Your journal memories for it are removed from this iPhone."
        }
        return "Its itinerary, packing list, expenses and memories will be removed from this iPhone and your cloud backup."
    }

    func loadWeather() async {
        guard let trip else { return }
        weather = try? await weatherService.forecast(for: trip)
    }
}

// Add / edit activity sheet
@MainActor
@Observable
final class ActivityFormViewModel {
    let tripID: UUID
    // nil when adding
    let activityID: UUID?
    private let store: TripStore

    var title = ""
    var place = ""
    var day: Int
    var time: Date
    var effort: Effort = .moderate
    var isOutdoor = false

    init(tripID: UUID, day: Int, activityID: UUID? = nil, store: TripStore, clock: Clock) {
        self.tripID = tripID
        self.activityID = activityID
        self.store = store
        self.day = day
        let today = Calendar.trip.startOfDay(for: clock.now)
        time = Calendar.trip.date(today, atMinutes: 9 * 60)

        if let activityID, let activity = store.trip(tripID)?.activities.first(where: { $0.id == activityID }) {
            title = activity.title
            place = activity.place
            self.day = activity.day
            time = Calendar.trip.date(today, atMinutes: activity.minutes)
            effort = activity.effort
            isOutdoor = activity.isOutdoor
        }
    }

    var isEditing: Bool { activityID != nil }
    var screenTitle: String { isEditing ? "Edit Activity" : "Add Activity" }
    var saveTitle: String { isEditing ? "Save Changes" : "Add Activity" }

    var dayCount: Int { store.trip(tripID)?.dayCount ?? 1 }

    var placeHint: String { store.trip(tripID)?.mainPlace ?? "Ella" }

    var minutes: Int { Calendar.trip.minutesSinceMidnight(time) }

    var canSave: Bool { !title.trimmed.isEmpty }

    var effortIndex: Int {
        get { Effort.allCases.firstIndex(of: effort) ?? 0 }
        set { effort = Effort.allCases[newValue] }
    }

    // Just a warning, clashes are allowed
    var clashWarning: String? {
        guard let trip = store.trip(tripID),
              let clash = ItineraryPlanner.clashes(day: day, minutes: minutes, ignoring: activityID, in: trip.activities).first
        else { return nil }
        return "“\(clash.title)” is also at \(clash.timeText) on Day \(day)."
    }

    // false if invalid or the save failed
    func save() -> Bool {
        guard canSave, let trip = store.trip(tripID) else { return false }
        // Empty place uses the trip's main place
        let finalPlace = place.trimmed.isEmpty ? trip.mainPlace : place.trimmed
        let finalDay = min(max(day, 1), trip.dayCount)

        guard let activityID else {
            let activity = Activity(day: finalDay, title: title.trimmed, minutes: minutes, place: finalPlace,
                                    effort: effort, isOutdoor: isOutdoor)
            return store.updateTrip(tripID) { $0.activities.append(activity) }
        }

        return store.updateTrip(tripID) { trip in
            guard let index = trip.activities.firstIndex(where: { $0.id == activityID }) else { return }
            trip.activities[index].title = title.trimmed
            trip.activities[index].place = finalPlace
            trip.activities[index].day = finalDay
            trip.activities[index].minutes = minutes
            trip.activities[index].effort = effort
            trip.activities[index].isOutdoor = isOutdoor
        }
    }

    func delete() -> Bool {
        guard let activityID else { return false }
        return store.updateTrip(tripID) { trip in
            trip.activities.removeAll { $0.id == activityID }
        }
    }
}

@MainActor
@Observable
final class PackingViewModel {
    let tripID: UUID
    private let store: TripStore
    private let weatherService: WeatherService

    private(set) var weather: WeatherSnapshot?

    init(tripID: UUID, store: TripStore, weather: WeatherService) {
        self.tripID = tripID
        self.store = store
        self.weatherService = weather
    }

    var trip: Trip? { store.trip(tripID) }

    var categories: [String] { PackingAdvisor.orderedCategories(in: trip?.packing ?? []) }

    func items(in category: String) -> [PackingItem] {
        trip?.packing.filter { $0.category == category } ?? []
    }

    var progress: Double { trip?.packingProgress ?? 0 }

    var isComplete: Bool { !(trip?.packing.isEmpty ?? true) && progress == 1 }

    var packedText: String { "\(trip?.packedCount ?? 0) / \(trip?.packing.count ?? 0) packed" }

    var suggestions: [PackingSuggestion] {
        guard let trip else { return [] }
        return PackingAdvisor.suggestions(for: trip, forecast: weather)
    }

    func toggle(_ item: PackingItem) {
        store.updateTrip(tripID) { trip in
            guard let index = trip.packing.firstIndex(where: { $0.id == item.id }) else { return }
            trip.packing[index].isPacked.toggle()
        }
    }

    // Skips empty names and duplicates
    func addItem(named rawName: String, category: String) {
        let name = rawName.trimmed
        guard !name.isEmpty, let trip,
              !trip.packing.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        store.updateTrip(tripID) { $0.packing.append(PackingItem(name: name, category: category)) }
    }

    func add(_ suggestion: PackingSuggestion) {
        addItem(named: suggestion.item, category: suggestion.category)
    }

    func delete(_ item: PackingItem) {
        store.updateTrip(tripID) { trip in
            trip.packing.removeAll { $0.id == item.id }
        }
    }

    func resetToTemplate() {
        store.updateTrip(tripID) { $0.packing = PackingAdvisor.defaultTemplate() }
    }

    func loadWeather() async {
        guard let trip else { return }
        weather = try? await weatherService.forecast(for: trip)
    }
}
