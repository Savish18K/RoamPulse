import Foundation
import Observation

/// Home tab: what matters right now.
///
/// Home has four states, in this order of priority:
/// - a trip is **active**: today's plan, weather, budget, latest memory and quick actions;
/// - one is **coming up**: a countdown and a "get ready" checklist;
/// - all trips are **finished**: a recap of the last one and a nudge to plan the next;
/// - there are **no trips**: a welcome with ways to start.
@MainActor
@Observable
final class HomeViewModel {
    enum State: Equatable {
        case noTrips
        case active(UUID)
        case upcoming(UUID)
        case completed(UUID)
    }

    /// A line of the "Get ready" checklist before a trip.
    struct ReadinessItem: Identifiable, Equatable {
        let id: String
        let icon: String
        let title: String
        let detail: String
        let isDone: Bool
        let route: AppRoute?
    }

    private let store: TripStore
    private let clock: Clock
    private let weatherService: WeatherService

    private(set) var weather: WeatherSnapshot?
    private(set) var weatherError: String?
    private(set) var isLoadingWeather = false

    init(store: TripStore, clock: Clock, weather: WeatherService) {
        self.store = store
        self.clock = clock
        self.weatherService = weather
    }

    var now: Date { clock.now }

    var state: State {
        if let trip = store.activeTrip { return .active(trip.id) }
        if let trip = store.upcomingTrips.first { return .upcoming(trip.id) }
        if let trip = store.completedTrips.first { return .completed(trip.id) }
        return .noTrips
    }

    /// The trip Home is about, whatever the state.
    var featuredTrip: Trip? {
        switch state {
        case .active(let id), .upcoming(let id), .completed(let id): store.trip(id)
        case .noTrips: nil
        }
    }

    /// The trip happening today, if there is one.
    var activeTrip: Trip? { store.activeTrip }

    /// The trip that Add Expense and New Memory apply to.
    var currentTrip: Trip? { store.currentTrip }

    /// The next trip after the one being shown.
    var nextUpcomingTrip: Trip? {
        store.upcomingTrips.first { $0.id != featuredTrip?.id }
    }

    var latestMemory: Memory? { store.latestMemory }

    var myInitials: String { store.me.initials }

    /// Joining a friend's trip needs an account (cloud sync).
    var canJoinTrips: Bool { store.accountID != nil }

    var dateText: String { now.text("EEEE, d MMMM") }

    var greeting: String {
        switch Calendar.trip.component(.hour, from: now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    func statusText(for trip: Trip) -> String { trip.statusText(at: now) }

    func daysUntilStart(of trip: Trip) -> Int { trip.daysUntilStart(from: now) }

    /// "Tomorrow", "In 1 day" style text for the countdown.
    func countdownText(for trip: Trip) -> String {
        let days = daysUntilStart(of: trip)
        return days == 1 ? "Tomorrow" : "In \(days) days"
    }

    /// e.g. countdown "Next · in 50 min", detail "17:30 Nine Arch Bridge viewpoint".
    func nextActivity(in trip: Trip) -> (countdown: String, detail: String)? {
        guard let next = trip.nextActivity(at: now) else { return nil }
        let minutes = next.minutes - Calendar.trip.minutesSinceMidnight(now)
        let countdown = minutes < 60 ? "in \(minutes) min" : "in \(minutes / 60) h \(minutes % 60) min"
        return ("Next · \(countdown)", "\(next.timeText) \(next.title)")
    }

    /// Today's activities on the active trip, in time order.
    func todaysActivities(in trip: Trip) -> [Activity] {
        guard let day = trip.dayNumber(at: now) else { return [] }
        return trip.activities(onDay: day)
    }

    /// Your own balance on the trip, from the settle-up maths.
    func myBalance(in trip: Trip) -> Balance? {
        ExpenseCalculator.balances(for: trip).first { $0.member.isMe }
    }

    func recentExpenses(in trip: Trip) -> [Expense] {
        Array(trip.expenses.sorted { $0.date > $1.date }.prefix(2))
    }

    func latestMemory(in trip: Trip) -> Memory? {
        store.memories(inTrip: trip.id).first
    }

    /// The next outdoor activity at risk on the featured trip.
    var advisory: WeatherAdvisory? {
        guard let trip = featuredTrip else { return nil }
        return WeatherAdvisor.headline(for: trip, snapshot: weather, now: now)
    }

    /// The forecast covers about 5 days, so a trip further away has no weather yet.
    func forecastIsAvailable(for trip: Trip) -> Bool {
        trip.status(at: now) == .active || daysUntilStart(of: trip) <= 4
    }

    /// e.g. "The forecast appears on Mon 5 Jan."
    func forecastNote(for trip: Trip) -> String {
        let from = Calendar.trip.date(byAdding: .day, value: -4, to: trip.startDate) ?? trip.startDate
        return "The forecast for \(trip.mainPlace) appears on \(from.text("EEE d MMM"))."
    }

    /// What is ready and what still needs doing before the trip.
    func readiness(for trip: Trip) -> [ReadinessItem] {
        let plannedDays = Set(trip.activities.map(\.day)).count
        return [
            ReadinessItem(
                id: "packing", icon: "bag", title: "Packing",
                detail: trip.packing.isEmpty ? "No list yet" : "\(trip.packedCount) of \(trip.packing.count) packed",
                isDone: !trip.packing.isEmpty && trip.packingProgress == 1, route: .packing(trip.id)),
            ReadinessItem(
                id: "plan", icon: "calendar", title: "Itinerary",
                detail: trip.activities.isEmpty
                    ? "Nothing planned yet"
                    : "\(trip.activities.count) activities over \(plannedDays) of \(trip.dayCount) days",
                isDone: plannedDays == trip.dayCount, route: .tripDetail(trip.id)),
            ReadinessItem(
                id: "budget", icon: "creditcard", title: "Budget",
                detail: trip.budget > 0 ? "\(trip.budget.lkr) set" : "No budget set",
                isDone: trip.budget > 0, route: .expenses(trip.id)),
            ReadinessItem(
                id: "people", icon: "person.2", title: "Companions",
                detail: trip.members.count > 1 ? trip.members.map(\.name).joined(separator: ", ") : "Just you so far",
                isDone: trip.members.count > 1, route: nil),
        ]
    }

    func memoriesCount(in trip: Trip) -> Int { store.memories(inTrip: trip.id).count }

    /// Photos from the trip's memories, for the recap.
    func recapPhotos(for trip: Trip) -> [MemoryPhoto] {
        Array(store.memories(inTrip: trip.id).flatMap(\.photos).prefix(4))
    }

    /// Loads the forecast for an active trip, or an upcoming one within the forecast range.
    func loadWeather() async {
        guard let trip = featuredTrip, trip.status(at: now) != .completed, forecastIsAvailable(for: trip) else {
            weather = nil
            weatherError = nil
            return
        }
        isLoadingWeather = true
        defer { isLoadingWeather = false }
        do {
            weather = try await weatherService.forecast(for: trip)
            weatherError = nil
        } catch {
            weather = nil
            weatherError = error.localizedDescription
        }
    }
}
