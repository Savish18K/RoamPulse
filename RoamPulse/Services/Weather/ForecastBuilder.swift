import Foundation

/// Turns OpenWeatherMap's responses into the `WeatherSnapshot` the screens show.
/// A pure function of its inputs (no network, no clock), so it is unit tested with saved JSON.
enum ForecastBuilder {
    /// - Parameters:
    ///   - now: steps that have already ended are dropped, so an old cached forecast still starts "now".
    ///   - fetchedAt: when the data was downloaded.
    static func snapshot(from bundle: OpenWeatherMapBundle, for trip: Trip, now: Date, fetchedAt: Date,
                         isOffline: Bool) -> WeatherSnapshot {
        let calendar = Calendar.trip
        let slots = bundle.forecast.list.map(slot).filter { $0.end > now }

        // "Current" conditions: the download's, unless it is over 3 hours old (an old cache),
        // in which case the forecast step for now is closer to the truth.
        let current = bundle.current
        let currentCondition = current.weather.first
        let staleCurrent = now.timeIntervalSince(fetchedAt) > ForecastSlot.length
        let nowSlot = slots.first
        let temperature = staleCurrent ? (nowSlot?.temperature ?? Int(current.main.temp.rounded()))
                                       : Int(current.main.temp.rounded())
        let condition = staleCurrent ? (nowSlot?.condition ?? text(currentCondition))
                                     : text(currentCondition)
        let symbol = staleCurrent ? (nowSlot?.symbol ?? "cloud")
                                  : symbol(code: currentCondition?.id ?? 800, icon: currentCondition?.icon ?? "01d")

        let today = calendar.startOfDay(for: now)
        let todayTemperatures = slots.filter { calendar.isDate($0.start, inSameDayAs: today) }.map(\.temperature)
            + [temperature]
        let high = max(todayTemperatures.max() ?? temperature, staleCurrent ? Int.min : Int(current.main.tempMax.rounded()))
        let low = min(todayTemperatures.min() ?? temperature, staleCurrent ? Int.max : Int(current.main.tempMin.rounded()))

        let hourly = [HourlyForecast(label: "Now", temperature: temperature, rainChance: nowSlot?.rainChance ?? 0,
                                     symbol: symbol)]
            + slots.prefix(5).map { HourlyForecast(label: $0.start.text("HH:mm"), temperature: $0.temperature,
                                                   rainChance: $0.rainChance, symbol: $0.symbol) }

        return WeatherSnapshot(
            location: bundle.placeName,
            condition: condition,
            symbol: symbol,
            temperature: temperature,
            high: high,
            low: low,
            humidity: current.main.humidity,
            windKmh: Int((current.wind.speed * 3.6).rounded()),
            rainChance: nowSlot?.rainChance ?? 0,
            sunset: current.sys.sunset.map { Date(timeIntervalSince1970: $0).text("HH:mm") } ?? "–",
            fetchedAt: fetchedAt,
            hourly: hourly,
            daily: daily(from: slots, trip: trip),
            slots: slots,
            isOffline: isOffline,
            source: .openWeatherMap
        )
    }

    static func slot(from item: OWMForecast.Item) -> ForecastSlot {
        let condition = item.weather.first
        return ForecastSlot(
            start: Date(timeIntervalSince1970: item.dt),
            temperature: Int(item.main.temp.rounded()),
            rainChance: Int(((item.pop ?? 0) * 100).rounded()),
            rainMM: (item.rain?.threeHours ?? 0) + (item.snow?.threeHours ?? 0),
            conditionCode: condition?.id ?? 800,
            condition: text(condition),
            symbol: symbol(code: condition?.id ?? 800, icon: condition?.icon ?? "01d")
        )
    }

    /// One row per day (up to 5), with the trip day number when the day is part of the trip.
    static func daily(from slots: [ForecastSlot], trip: Trip) -> [DailyForecast] {
        let calendar = Calendar.trip
        let days = Dictionary(grouping: slots) { calendar.startOfDay(for: $0.start) }
        return days.keys.sorted().prefix(5).compactMap { day -> DailyForecast? in
            guard let daySlots = days[day], !daySlots.isEmpty else { return nil }
            let wettest = daySlots.max { $0.rainChance < $1.rainChance } ?? daySlots[0]
            // Show the wettest step's weather if rain is likely, otherwise the weather around midday.
            let midday = calendar.date(day, atMinutes: 12 * 60)
            let representative = wettest.rainChance >= 50 || wettest.isStormy
                ? wettest
                : daySlots.min { abs($0.start.timeIntervalSince(midday)) < abs($1.start.timeIntervalSince(midday)) } ?? wettest
            let dayNumber = calendar.days(from: trip.startDate, to: day) + 1
            return DailyForecast(
                dayLabel: day.text("EEE d"),
                tripDay: (1...trip.dayCount).contains(dayNumber) ? dayNumber : nil,
                condition: representative.condition,
                symbol: representative.symbol,
                rainChance: wettest.rainChance >= 20 ? wettest.rainChance : nil,
                high: daySlots.map(\.temperature).max() ?? 0,
                low: daySlots.map(\.temperature).min() ?? 0
            )
        }
    }

    /// "light rain" → "Light rain"
    static func text(_ condition: OWMCondition?) -> String {
        guard let description = condition?.description, let first = description.first else { return "–" }
        return first.uppercased() + description.dropFirst()
    }

    /// SF Symbol for an OpenWeatherMap condition code. `icon` ends in "n" at night.
    static func symbol(code: Int, icon: String) -> String {
        let night = icon.hasSuffix("n")
        switch code {
        case 200..<300: return "cloud.bolt.rain.fill"
        case 300..<400: return "cloud.drizzle.fill"
        case 500, 501: return night ? "cloud.moon.rain.fill" : "cloud.rain.fill"
        case 502...504, 520..<532: return "cloud.heavyrain.fill"
        case 511, 611..<620: return "cloud.sleet.fill"
        case 600..<700: return "cloud.snow.fill"
        case 781: return "tornado"
        case 700..<800: return "cloud.fog.fill"
        case 800: return night ? "moon.stars.fill" : "sun.max.fill"
        case 801, 802: return night ? "cloud.moon.fill" : "cloud.sun.fill"
        default: return "cloud.fill"
        }
    }
}
