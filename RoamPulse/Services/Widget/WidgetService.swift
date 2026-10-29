import Foundation
import WidgetKit

// Saves what the Home Screen widget shows. A protocol so tests don't write to the real App Group
protocol WidgetStoring {
    func save(_ snapshot: WidgetSnapshot?) throws
}

struct AppGroupWidgetStore: WidgetStoring {
    func save(_ snapshot: WidgetSnapshot?) throws {
        try WidgetSnapshot.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
    }
}

// Picks the trip for the widget and turns it into a snapshot. No side effects, so it's unit tested
enum WidgetPlanner {
    // Plenty for today and tomorrow on a busy trip
    static let maxStops = 12
    // Two days of 3-hour forecast steps
    static let maxForecastSteps = 16

    // Today's trip, otherwise the next one. Finished trips aren't shown
    static func featuredTrip(in trips: [Trip], now: Date) -> Trip? {
        let sections = trips.sections(at: now)
        return sections.active.first ?? sections.upcoming.first
    }

    static func snapshot(for trip: Trip, forecast: WeatherSnapshot?, now: Date) -> WidgetSnapshot {
        let stops = trip.activities
            .filter { !$0.isDone }
            .map { (activity: $0, start: WeatherAdvisor.startDate(of: $0, in: trip)) }
            .filter { $0.start >= now }
            .sorted { $0.start < $1.start }
            .prefix(maxStops)
            .map { activity, start in
                // Same rules as the trip screen and the weather alerts
                let advisory = WeatherAdvisor.advisory(for: activity, in: trip, snapshot: forecast)
                return WidgetSnapshot.Stop(id: activity.id, title: activity.title, place: activity.place, start: start,
                                           day: activity.day, advisory: advisory.map { "\($0.title) \($0.window)" })
            }
        let steps = (forecast?.slots ?? [])
            .filter { $0.end > now }
            .prefix(maxForecastSteps)
            .map { WidgetSnapshot.Forecast(start: $0.start, end: $0.end, temperature: $0.temperature, symbol: $0.symbol,
                                           condition: $0.condition) }
        return WidgetSnapshot(tripID: trip.id, tripName: trip.name, place: trip.mainPlace,
                              firstDay: Calendar.trip.startOfDay(for: trip.startDate), dayCount: trip.dayCount,
                              stops: Array(stops), forecast: Array(steps))
    }
}

// Keeps the widget in step with the app. Called when trips or the forecast change and when the app opens
@MainActor
final class WidgetService {
    private let storage: WidgetStoring
    private let weather: WeatherService
    private let clock: Clock
    // Only written (and the widget reloaded) when something changed
    private var saved: WidgetSnapshot?
    private var hasSaved = false

    init(storage: WidgetStoring, weather: WeatherService, clock: Clock) {
        self.storage = storage
        self.weather = weather
        self.clock = clock
    }

    func update(trips: [Trip]) async {
        let now = clock.now
        guard let trip = WidgetPlanner.featuredTrip(in: trips, now: now) else {
            save(nil)
            return
        }
        // The forecast covers about 5 days, and offline the saved one is used
        let forecast = trip.daysUntilStart(from: now) <= 4 ? try? await weather.forecast(for: trip) : nil
        save(WidgetPlanner.snapshot(for: trip, forecast: forecast, now: now))
    }

    // After signing out, so the next person doesn't see someone else's trip
    func clear() {
        save(nil)
    }

    private func save(_ snapshot: WidgetSnapshot?) {
        guard !hasSaved || snapshot != saved else { return }
        do {
            try storage.save(snapshot)
            saved = snapshot
            hasSaved = true
        } catch {
            // Not worth bothering the user, the widget keeps what it had
        }
    }
}
