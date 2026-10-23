import Foundation

/// Gives the forecast for a trip's destination, and finds places for the Create Trip form.
///
/// The app uses `OpenWeatherMapService` (live data, cached for offline use). Without an API key,
/// and in previews and tests, `MockWeatherService` returns sample data shaped the same way.
@MainActor
protocol WeatherService: AnyObject {
    /// - Parameter refresh: true for pull-to-refresh: always download, even if the saved forecast is recent.
    func forecast(for trip: Trip, refresh: Bool) async throws -> WeatherSnapshot
    /// Places matching what the user typed, for the destination suggestions.
    func searchPlaces(_ query: String) async throws -> [Place]
}

extension WeatherService {
    func forecast(for trip: Trip) async throws -> WeatherSnapshot {
        try await forecast(for: trip, refresh: false)
    }
}

/// A destination suggestion with its coordinates.
struct Place: Hashable, Identifiable {
    var name: String
    /// e.g. "Uva Province, LK"
    var region: String
    var latitude: Double
    var longitude: Double

    var id: String { "\(name)-\(latitude)-\(longitude)" }
}

/// Sample forecast that looks like the prototype: light rain today, heavy rain tomorrow afternoon.
/// The days are worked out from the clock, so they always line up with "today".
@MainActor
final class MockWeatherService: WeatherService {
    let clock: Clock

    init(clock: Clock) {
        self.clock = clock
    }

    /// Weather per 3-hour step for each of the next five days, as (condition code, rain %, temperature).
    private static let sampleDays: [[(code: Int, rain: Int, temperature: Int)]] = [
        // Today: light rain in the afternoon.
        [(803, 10, 15), (803, 10, 16), (500, 30, 19), (500, 50, 21), (500, 70, 20), (500, 60, 18), (803, 30, 17), (803, 20, 16)],
        // Tomorrow: dry morning, heavy rain 14:00–17:00 (the prototype's Day 3 advisory).
        [(801, 10, 15), (801, 10, 16), (802, 20, 19), (500, 40, 20), (502, 90, 19), (501, 70, 18), (803, 30, 16), (803, 20, 15)],
        [(803, 10, 16), (803, 10, 17), (803, 20, 21), (803, 20, 23), (802, 20, 22), (803, 10, 19), (803, 10, 17), (803, 10, 16)],
        [(800, 0, 16), (800, 0, 17), (801, 10, 22), (802, 10, 24), (802, 10, 23), (801, 10, 20), (800, 0, 18), (800, 0, 16)],
        [(803, 10, 15), (803, 20, 16), (500, 40, 20), (500, 40, 23), (500, 30, 22), (803, 20, 19), (803, 10, 17), (803, 10, 15)],
    ]

    private static let descriptions = [500: "Light rain", 501: "Moderate rain", 502: "Heavy rain", 800: "Clear sky",
                                       801: "Few clouds", 802: "Scattered clouds", 803: "Cloudy"]

    func forecast(for trip: Trip, refresh: Bool) async throws -> WeatherSnapshot {
        let calendar = Calendar.trip
        let now = clock.now
        let today = calendar.startOfDay(for: now)

        var slots: [ForecastSlot] = []
        for (dayOffset, steps) in Self.sampleDays.enumerated() {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            for (index, step) in steps.enumerated() {
                let start = calendar.date(day, atMinutes: index * 180)
                slots.append(ForecastSlot(
                    start: start, temperature: step.temperature, rainChance: step.rain,
                    rainMM: step.code == 502 ? 6 : (step.code >= 500 && step.code < 600 ? 1 : 0),
                    conditionCode: step.code, condition: Self.descriptions[step.code] ?? "Cloudy",
                    symbol: ForecastBuilder.symbol(code: step.code, icon: "01d")))
            }
        }
        slots = slots.filter { $0.end > now }

        let current = slots.first
        let hourly = [HourlyForecast(label: "Now", temperature: current?.temperature ?? 19,
                                     rainChance: current?.rainChance ?? 0, symbol: current?.symbol ?? "cloud.drizzle.fill")]
            + slots.prefix(5).map { HourlyForecast(label: $0.start.text("HH:mm"), temperature: $0.temperature,
                                                   rainChance: $0.rainChance, symbol: $0.symbol) }

        return WeatherSnapshot(
            location: trip.mainPlace,
            condition: current?.condition ?? "Light rain",
            symbol: current?.symbol ?? "cloud.drizzle.fill",
            temperature: current?.temperature ?? 19,
            high: 22, low: 15,
            humidity: 88, windKmh: 11, rainChance: current?.rainChance ?? 70,
            sunset: "18:02",
            fetchedAt: now,
            hourly: hourly,
            daily: ForecastBuilder.daily(from: slots, trip: trip),
            slots: slots,
            source: .sample
        )
    }

    /// A few Sri Lankan destinations, so the form's suggestions work without an API key.
    static let samplePlaces = [
        Place(name: "Ella", region: "Uva Province, LK", latitude: 6.8667, longitude: 81.0466),
        Place(name: "Kandy", region: "Central Province, LK", latitude: 7.2906, longitude: 80.6337),
        Place(name: "Galle", region: "Southern Province, LK", latitude: 6.0329, longitude: 80.2170),
        Place(name: "Unawatuna", region: "Southern Province, LK", latitude: 6.0097, longitude: 80.2506),
        Place(name: "Hikkaduwa", region: "Southern Province, LK", latitude: 6.1395, longitude: 80.1063),
        Place(name: "Mirissa", region: "Southern Province, LK", latitude: 5.9483, longitude: 80.4716),
        Place(name: "Jaffna", region: "Northern Province, LK", latitude: 9.6615, longitude: 80.0255),
        Place(name: "Sigiriya", region: "Central Province, LK", latitude: 7.9570, longitude: 80.7603),
        Place(name: "Colombo", region: "Western Province, LK", latitude: 6.9271, longitude: 79.8612),
        Place(name: "Nuwara Eliya", region: "Central Province, LK", latitude: 6.9497, longitude: 80.7891),
    ]

    func searchPlaces(_ query: String) async throws -> [Place] {
        Self.samplePlaces.filter { $0.name.localizedCaseInsensitiveContains(query.trimmed) }
    }
}

/// Weather advice for the itinerary: which outdoor activity is at risk, when, and a better time.
///
/// Each outdoor activity is checked against the 3-hour forecast step it falls in:
/// - thunderstorm, or rain chance ≥ 60%, or ≥ 3 mm of rain → a rain/storm warning, with the
///   driest daytime step that day suggested instead;
/// - a high-effort activity at 32°C or more → a heat warning.
/// Activities beyond the 5-day forecast, indoor ones and finished ones get no warning.
enum WeatherAdvisor {
    /// Rain chance (%) in a 3-hour step at which outdoor plans get a warning.
    static let rainThreshold = 60
    /// Rain (mm in 3 hours) that is a warning whatever the chance.
    static let heavyRainMM = 3.0
    /// Temperature (°C) at which high-effort activities get a warning.
    static let heatThreshold = 32

    /// The forecast for one trip day, or nil when that day is outside the forecast range.
    static func forecast(forDay day: Int, in snapshot: WeatherSnapshot?) -> DailyForecast? {
        snapshot?.daily.first { $0.tripDay == day }
    }

    /// When the activity starts.
    static func startDate(of activity: Activity, in trip: Trip) -> Date {
        Calendar.trip.date(trip.date(ofDay: activity.day), atMinutes: activity.minutes)
    }

    /// The 3-hour step covering `date`. A time just before the first step (it starts at the next
    /// whole 3 hours) uses the first step.
    static func slot(covering date: Date, in slots: [ForecastSlot]) -> ForecastSlot? {
        if let slot = slots.first(where: { $0.start <= date && date < $0.end }) {
            return slot
        }
        if let first = slots.first, date < first.start, first.start.timeIntervalSince(date) < ForecastSlot.length {
            return first
        }
        return nil
    }

    static func isWet(_ slot: ForecastSlot) -> Bool {
        slot.isStormy || slot.rainChance >= rainThreshold || slot.rainMM >= heavyRainMM
    }

    /// Warning for one activity, or nil if the weather looks fine (or isn't known yet).
    static func advisory(for activity: Activity, in trip: Trip, snapshot: WeatherSnapshot?) -> ActivityAdvisory? {
        guard activity.isOutdoor, !activity.isDone, let snapshot else { return nil }
        let start = startDate(of: activity, in: trip)
        guard let slot = slot(covering: start, in: snapshot.slots) else { return nil }

        if isWet(slot) {
            let run = wetRun(around: slot, in: snapshot.slots)
            let window = "\(run.start.text("HH:mm"))–\(run.end.text("HH:mm"))"
            let title: String
            if slot.isStormy {
                title = "Thunderstorms likely"
            } else if slot.rainChance >= 80 || slot.rainMM >= heavyRainMM {
                title = "Heavy rain likely"
            } else {
                title = "Rain likely"
            }
            var message = "\(title) \(window) (\(slot.rainChance)%)."
            if let drier = drierSlot(sameDayAs: start, in: snapshot.slots) {
                message += " Drier around \(drier.start.text("HH:mm")) (\(drier.rainChance)%)."
            } else {
                message += " Consider an indoor plan."
            }
            return ActivityAdvisory(activityID: activity.id, day: activity.day, kind: slot.isStormy ? .storm : .rain,
                                    title: title, window: window, windowStart: run.start, message: message)
        }

        if activity.effort == .high && slot.temperature >= heatThreshold {
            let window = "\(slot.start.text("HH:mm"))–\(slot.end.text("HH:mm"))"
            return ActivityAdvisory(activityID: activity.id, day: activity.day, kind: .heat, title: "Very hot",
                                    window: window, windowStart: slot.start,
                                    message: "Very hot (\(slot.temperature)°) \(window). Start early and carry plenty of water.")
        }
        return nil
    }

    /// All warnings for the trip, in plan order.
    static func advisories(for trip: Trip, snapshot: WeatherSnapshot?) -> [ActivityAdvisory] {
        trip.activities
            .sorted { ($0.day, $0.minutes) < ($1.day, $1.minutes) }
            .compactMap { advisory(for: $0, in: trip, snapshot: snapshot) }
    }

    /// Days with at least one outdoor activity at risk. These get an orange dot on the day tabs.
    static func advisoryDays(for trip: Trip, in snapshot: WeatherSnapshot?) -> Set<Int> {
        Set(advisories(for: trip, snapshot: snapshot).map(\.day))
    }

    /// The headline for Home and the Weather screen: the next activity at risk.
    static func headline(for trip: Trip, snapshot: WeatherSnapshot?, now: Date) -> WeatherAdvisory? {
        guard let first = advisories(for: trip, snapshot: snapshot).first(where: { advisory in
            guard let activity = trip.activities.first(where: { $0.id == advisory.activityID }) else { return false }
            return startDate(of: activity, in: trip) >= now
        }), let activity = trip.activities.first(where: { $0.id == first.activityID }) else { return nil }

        let weekday = trip.date(ofDay: first.day).text("EEE")
        return WeatherAdvisory(
            day: first.day,
            title: "\(first.title) • \(weekday)",
            shortMessage: "\(activity.title) at \(activity.timeText): \(first.title.lowercased()) \(first.window).",
            message: "\(activity.title) (Day \(first.day), \(activity.timeText)): \(first.message)"
        )
    }

    /// The wet steps next to each other around `slot`, as one time window (e.g. 14:00–20:00).
    private static func wetRun(around slot: ForecastSlot, in slots: [ForecastSlot]) -> (start: Date, end: Date) {
        guard let index = slots.firstIndex(of: slot) else { return (slot.start, slot.end) }
        var first = index
        var last = index
        while first > 0, isWet(slots[first - 1]), slots[first - 1].end == slots[first].start {
            first -= 1
        }
        while last + 1 < slots.count, isWet(slots[last + 1]), slots[last].end == slots[last + 1].start {
            last += 1
        }
        return (slots[first].start, slots[last].end)
    }

    /// The driest dry step between 06:00 and 18:00 on the same day.
    private static func drierSlot(sameDayAs date: Date, in slots: [ForecastSlot]) -> ForecastSlot? {
        let calendar = Calendar.trip
        return slots
            .filter { slot in
                let hour = calendar.component(.hour, from: slot.start)
                return calendar.isDate(slot.start, inSameDayAs: date) && (6...15).contains(hour) && !isWet(slot)
            }
            .min { ($0.rainChance, $0.start) < ($1.rainChance, $1.start) }
    }
}
