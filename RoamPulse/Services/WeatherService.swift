import Foundation

// Weather protocol, OpenWeatherMap in the app and a mock without an API key
@MainActor
protocol WeatherService: AnyObject {
    // refresh = true always downloads (pull to refresh)
    func forecast(for trip: Trip, refresh: Bool) async throws -> WeatherSnapshot
    func searchPlaces(_ query: String) async throws -> [Place]
}

extension WeatherService {
    func forecast(for trip: Trip) async throws -> WeatherSnapshot {
        try await forecast(for: trip, refresh: false)
    }
}

struct Place: Hashable, Identifiable {
    var name: String
    // e.g. "Uva Province, LK"
    var region: String
    var latitude: Double
    var longitude: Double

    var id: String { "\(name)-\(latitude)-\(longitude)" }
}

// Fake forecast based on the prototype, dates follow the clock
@MainActor
final class MockWeatherService: WeatherService {
    let clock: Clock

    init(clock: Clock) {
        self.clock = clock
    }

    // (condition code, rain %, temperature) per 3 hour step
    private static let sampleDays: [[(code: Int, rain: Int, temperature: Int)]] = [
        // Today: light rain in the afternoon
        [(803, 10, 15), (803, 10, 16), (500, 30, 19), (500, 50, 21), (500, 70, 20), (500, 60, 18), (803, 30, 17), (803, 20, 16)],
        // Tomorrow: heavy rain 14:00-17:00
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

    // So the place search works without an API key
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

// Warns about outdoor activities in rain/storms (with a drier time) or high effort ones in the heat
enum WeatherAdvisor {
    // %
    static let rainThreshold = 60
    // mm in 3 hours
    static let heavyRainMM = 3.0
    // °C
    static let heatThreshold = 32

    // nil if the day is outside the forecast
    static func forecast(forDay day: Int, in snapshot: WeatherSnapshot?) -> DailyForecast? {
        snapshot?.daily.first { $0.tripDay == day }
    }

    static func startDate(of activity: Activity, in trip: Trip) -> Date {
        Calendar.trip.date(trip.date(ofDay: activity.day), atMinutes: activity.minutes)
    }

    // Times before the first step use the first step
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

    // nil if the weather looks fine
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

    static func advisories(for trip: Trip, snapshot: WeatherSnapshot?) -> [ActivityAdvisory] {
        trip.activities
            .sorted { ($0.day, $0.minutes) < ($1.day, $1.minutes) }
            .compactMap { advisory(for: $0, in: trip, snapshot: snapshot) }
    }

    // Days that get an orange dot
    static func advisoryDays(for trip: Trip, in snapshot: WeatherSnapshot?) -> Set<Int> {
        Set(advisories(for: trip, snapshot: snapshot).map(\.day))
    }

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

    // Joins the wet steps around slot into one window
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

    // Driest step between 06:00 and 18:00
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
