import Foundation

// What the app hands to the Home Screen widget. The app writes it as JSON into the shared App Group
// whenever trips or the forecast change; the widget only reads it, so it never needs Core Data or the network.
// Compiled into both the app and the widget extension.
struct WidgetSnapshot: Codable, Equatable {
    struct Stop: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
        var place: String
        var start: Date
        var day: Int
        // e.g. "Rain likely 12:00–18:00", nil when the weather looks fine
        var advisory: String?
    }

    // One 3-hour forecast step, so the widget shows the right weather later in the day too
    struct Forecast: Codable, Equatable {
        var start: Date
        var end: Date
        var temperature: Int
        var symbol: String
        var condition: String
    }

    var tripID: UUID
    var tripName: String
    // e.g. "Ella"
    var place: String
    // Midnight at the start of day 1
    var firstDay: Date
    var dayCount: Int
    // Not done yet and not started yet, in time order
    var stops: [Stop]
    var forecast: [Forecast]

    // What the widget should show at a given time
    enum State: Equatable {
        case upcoming(daysToGo: Int, first: Stop?)
        case active(day: Int, next: Stop?)
        case finished
    }

    func state(at date: Date, calendar: Calendar = .current) -> State {
        let day = calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: date)).day ?? 0
        if day < 0 { return .upcoming(daysToGo: -day, first: stops.first) }
        if day >= dayCount { return .finished }
        return .active(day: day + 1, next: nextStop(at: date))
    }

    // A stop stops being "next" once it starts. Timeline entries fall exactly on start times,
    // so this has to be "after", or the widget would keep showing a stop that has begun
    func nextStop(at date: Date) -> Stop? {
        stops.first { $0.start > date }
    }

    func forecast(at date: Date) -> Forecast? {
        forecast.first { $0.start <= date && date < $0.end }
    }

    // When the widget has to change by itself: as each stop starts (the next one takes over),
    // and at midnight for the day number or countdown. A week ahead is plenty, the app refreshes it before then
    func refreshDates(after date: Date, calendar: Calendar = .current) -> [Date] {
        let horizon = calendar.date(byAdding: .day, value: 7, to: date) ?? date
        let tripEnd = calendar.date(byAdding: .day, value: dayCount, to: firstDay) ?? firstDay
        var dates = stops.map(\.start)
        var midnight = calendar.startOfDay(for: date)
        while midnight <= min(tripEnd, horizon) {
            dates.append(midnight)
            guard let next = calendar.date(byAdding: .day, value: 1, to: midnight) else { break }
            midnight = next
        }
        return Array(Set(dates.filter { $0 > date && $0 <= horizon })).sorted()
    }
}

// Storage in the App Group container both targets can read
extension WidgetSnapshot {
    static let appGroup = "group.com.savishka.RoamPulse"
    // Must match the kind in the widget extension, used to reload it
    static let widgetKind = "NextStopWidget"

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "widget.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    // nil removes the file, e.g. after signing out
    static func save(_ snapshot: WidgetSnapshot?) throws {
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        if let snapshot {
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}

// Links from the widget into the app, e.g. roampulse://trip/<id>
enum WidgetLink: Equatable {
    case trip(UUID)
    case recordMemory(UUID)

    static let scheme = "roampulse"

    var tripID: UUID {
        switch self {
        case .trip(let id), .recordMemory(let id): id
        }
    }

    var url: URL {
        switch self {
        case .trip(let id): URL(string: "\(Self.scheme)://trip/\(id.uuidString)")!
        case .recordMemory(let id): URL(string: "\(Self.scheme)://record/\(id.uuidString)")!
        }
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let id = UUID(uuidString: url.lastPathComponent) else { return nil }
        switch url.host() {
        case "trip": self = .trip(id)
        case "record": self = .recordMemory(id)
        default: return nil
        }
    }
}
