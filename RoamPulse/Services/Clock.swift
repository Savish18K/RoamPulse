import Foundation

/// Where "now" comes from.
/// The app uses the real time (`SystemClock`); tests and previews use a `FixedClock`
/// so results don't change depending on when they run.
protocol Clock {
    var now: Date { get }
}

struct SystemClock: Clock {
    var now: Date { Date() }
}

struct FixedClock: Clock {
    var now: Date
}

extension Calendar {
    /// Gregorian calendar used for all trip day maths, whatever calendar the phone is set to.
    static let trip = Calendar(identifier: .gregorian)

    /// Whole days between the two dates, ignoring the time of day.
    /// e.g. Sat 22:00 → Sun 08:00 is 1 day.
    func days(from start: Date, to end: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: start), to: startOfDay(for: end)).day ?? 0
    }

    /// Minutes since midnight, e.g. 17:30 → 1050.
    func minutesSinceMidnight(_ date: Date) -> Int {
        let parts = dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// The given day at `minutes` past midnight.
    func date(_ day: Date, atMinutes minutes: Int) -> Date {
        date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }

    /// Builds a date from parts, e.g. `Calendar.trip.date(2026, 12, 13, 16, 40)`.
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
    }
}
