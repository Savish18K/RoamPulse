import Foundation
import Observation

/// Home tab: today's trip at a glance.
@MainActor
@Observable
final class HomeViewModel {
    private let store: TripStore
    private let clock: Clock
    private let weatherService: WeatherService

    private(set) var weather: WeatherSnapshot?

    init(store: TripStore, clock: Clock, weather: WeatherService) {
        self.store = store
        self.clock = clock
        self.weatherService = weather
    }

    var now: Date { clock.now }

    /// The trip happening today, if there is one.
    var activeTrip: Trip? { store.activeTrip }

    /// The trip that Add Expense and Record Memory apply to.
    var currentTrip: Trip? { store.currentTrip }

    var nextUpcomingTrip: Trip? { store.upcomingTrips.first }

    var latestMemory: Memory? { store.latestMemory }

    var myInitials: String { store.me.initials }

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

    /// e.g. countdown "Next · in 50 min", detail "17:30 Nine Arch Bridge viewpoint".
    func nextActivity(in trip: Trip) -> (countdown: String, detail: String)? {
        guard let next = trip.nextActivity(at: now) else { return nil }
        let minutes = next.minutes - Calendar.trip.minutesSinceMidnight(now)
        let countdown = minutes < 60 ? "in \(minutes) min" : "in \(minutes / 60) h \(minutes % 60) min"
        return ("Next · \(countdown)", "\(next.timeText) \(next.title)")
    }

    /// Your own balance on the trip, from the settle-up maths.
    func myBalance(in trip: Trip) -> Balance? {
        ExpenseCalculator.balances(for: trip).first { $0.member.isMe }
    }

    func recentExpenses(in trip: Trip) -> [Expense] {
        Array(trip.expenses.sorted { $0.date > $1.date }.prefix(2))
    }

    func loadWeather() async {
        guard let trip = activeTrip else {
            weather = nil
            return
        }
        // Home only shows a weather card, so if the forecast fails the card is simply hidden.
        weather = try? await weatherService.forecast(for: trip)
    }
}
