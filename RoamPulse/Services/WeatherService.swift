import Foundation

// MARK: - WeatherService

/// Gives the forecast for a trip's destination.
///
/// `MockWeatherService` returns sample data for now. Increment 7 adds an OpenWeatherMap
/// version behind this same protocol, so the view models that use it won't need to change.
protocol WeatherService {
    func forecast(for trip: Trip) async throws -> WeatherSnapshot
}

/// Sample forecast that looks like the prototype: light rain today, heavy rain tomorrow.
/// The days are worked out from the clock, so they always line up with "today".
struct MockWeatherService: WeatherService {
    let clock: Clock

    private struct SampleDay {
        let condition: String
        let symbol: String
        let rainChance: Int?
        let high: Int
        let low: Int
    }

    private static let sampleDays = [
        SampleDay(condition: "Light rain", symbol: "cloud.drizzle", rainChance: nil, high: 22, low: 15),
        SampleDay(condition: "Heavy rain", symbol: "cloud.heavyrain", rainChance: 90, high: 21, low: 15),
        SampleDay(condition: "Cloudy", symbol: "cloud", rainChance: nil, high: 23, low: 16),
        SampleDay(condition: "Partly sunny", symbol: "cloud.sun", rainChance: nil, high: 24, low: 16),
        SampleDay(condition: "Showers", symbol: "cloud.rain", rainChance: 40, high: 23, low: 15),
    ]

    func forecast(for trip: Trip) async throws -> WeatherSnapshot {
        let calendar = Calendar.trip
        let now = clock.now
        let today = calendar.startOfDay(for: now)

        var daily: [DailyForecast] = []
        var advisory: WeatherAdvisory?
        for (offset, sample) in Self.sampleDays.enumerated() {
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let dayNumber = calendar.days(from: trip.startDate, to: date) + 1
            let tripDay = (1...trip.dayCount).contains(dayNumber) ? dayNumber : nil
            daily.append(DailyForecast(dayLabel: date.text("EEE d"), tripDay: tripDay, condition: sample.condition,
                                       symbol: sample.symbol, rainChance: sample.rainChance,
                                       high: sample.high, low: sample.low))

            if advisory == nil, let tripDay, (sample.rainChance ?? 0) >= WeatherAdvisor.rainThreshold {
                advisory = WeatherAdvisory(
                    day: tripDay,
                    title: "\(sample.condition) Advisory • \(date.text("EEE"))",
                    shortMessage: "\(sample.condition) likely 14:00–17:00. Schedule outdoor sights early.",
                    message: "\(sample.condition) likely \(date.text("EEE")) 14:00 to 17:00. Outdoor activities on Day \(tripDay) may be affected."
                )
            }
        }

        let hourly = (0..<6).map { hour in
            let time = calendar.date(byAdding: .hour, value: hour, to: now) ?? now
            return HourlyForecast(label: hour == 0 ? "Now" : time.text("HH:00"),
                                  temperature: 19 - hour / 2,
                                  rainChance: max(70 - hour * 12, 10),
                                  symbol: hour < 3 ? "cloud.drizzle.fill" : "cloud.fill")
        }

        return WeatherSnapshot(
            location: trip.mainPlace,
            condition: "Light rain",
            symbol: "cloud.drizzle.fill",
            temperature: 19, high: 22, low: 15,
            humidity: 88, windKmh: 11, rainChance: 70,
            sunset: "18:02",
            updatedAt: now.text("HH:mm"),
            hourly: hourly,
            daily: daily,
            advisory: advisory
        )
    }
}

// MARK: - WeatherAdvisor

/// Simple weather rules used by the itinerary and the packing list.
/// Increment 7 replaces the whole-day check with one that looks at each activity's time slot.
enum WeatherAdvisor {
    /// Rain chance (%) at which outdoor plans get a warning.
    static let rainThreshold = 70

    /// The forecast for one trip day, or nil when that day is outside the forecast range.
    static func forecast(forDay day: Int, in snapshot: WeatherSnapshot?) -> DailyForecast? {
        snapshot?.daily.first { $0.tripDay == day }
    }

    /// Warning for an outdoor activity on a day where heavy rain is likely.
    static func advisory(for activity: Activity, in snapshot: WeatherSnapshot?) -> String? {
        guard activity.isOutdoor,
              let forecast = forecast(forDay: activity.day, in: snapshot),
              let rain = forecast.rainChance, rain >= rainThreshold else { return nil }
        return "\(forecast.condition) likely (\(rain)%). Try moving this earlier or to another day."
    }

    /// Days with at least one outdoor activity at risk. These get an orange dot on the day tabs.
    static func advisoryDays(for trip: Trip, in snapshot: WeatherSnapshot?) -> Set<Int> {
        Set(trip.activities.filter { advisory(for: $0, in: snapshot) != nil }.map(\.day))
    }
}
