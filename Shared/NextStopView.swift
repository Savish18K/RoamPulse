import SwiftUI
import WidgetKit

// The widget's content: the next stop of today's trip and any weather warning for it.
// Lives in Shared (not only in the extension) so the app's tests can render every size.
struct NextStopView: View {
    let snapshot: WidgetSnapshot?
    let date: Date
    let family: WidgetFamily

    // Same blue and purple as the app's buttons
    static let background = LinearGradient(colors: [Color(red: 0.04, green: 0.44, blue: 0.91),
                                                    Color(red: 0.55, green: 0.28, blue: 0.70)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var state: WidgetSnapshot.State? { snapshot?.state(at: date) }

    // Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 4)
            mainText
            Spacer(minLength: 4)
            footer
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            small
            if let snapshot, case .active = state {
                VStack(alignment: .trailing, spacing: 6) {
                    if let weather = snapshot.forecast(at: date) {
                        Image(systemName: weather.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.title)
                        Text("\(weather.temperature)°").font(.title2.bold())
                        Text(weather.condition).font(.caption).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Link(destination: WidgetLink.recordMemory(snapshot.tripID).url) {
                        Label("Record", systemImage: "mic.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.22), in: Capsule())
                    }
                    .accessibilityLabel("Record a memory")
                }
                .foregroundStyle(.white)
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(snapshot?.tripName ?? "RoamPulse")
                .font(.caption.bold())
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .opacity(0.8)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String? {
        guard let snapshot, let state else { return nil }
        switch state {
        case .active(let day, _): return "Day \(day) of \(snapshot.dayCount) • \(snapshot.place)"
        case .upcoming(let days, _): return days == 1 ? "Starts tomorrow" : "Starts in \(days) days"
        case .finished: return "Trip finished"
        }
    }

    @ViewBuilder
    private var mainText: some View {
        switch state {
        case .active(_, let next?), .upcoming(_, let next?):
            VStack(alignment: .leading, spacing: 2) {
                Text(whenText(for: next).uppercased())
                    .font(.caption2.bold())
                    .opacity(0.8)
                Text(next.title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
                if family == .systemMedium {
                    Text(next.start, style: .relative)
                        .font(.caption)
                        .opacity(0.8)
                }
            }
            .accessibilityElement(children: .combine)
        case .active:
            message("Nothing else planned", "Enjoy the rest of the day.")
        case .upcoming:
            message("Nothing planned yet", "Add activities in RoamPulse.")
        case .finished:
            message("Welcome back", "Open RoamPulse to look back on it.")
        case nil:
            message("No trip planned", "Plan one in RoamPulse.")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let advisory = nextStop?.advisory {
            Label(advisory, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.bold())
                .foregroundStyle(.yellow)
                .lineLimit(2)
                .accessibilityLabel("Weather warning: \(advisory)")
        } else if family == .systemSmall, case .active = state, let weather = snapshot?.forecast(at: date) {
            Label("\(weather.temperature)° \(weather.condition)", systemImage: weather.symbol)
                .font(.caption2)
                .lineLimit(1)
        }
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline).lineLimit(2)
            Text(detail).font(.caption).opacity(0.8).lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    // Lock Screen

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let next = nextStop {
                Text(whenText(for: next))
                    .font(.headline)
                    .widgetAccentable()
                Text(next.title)
                    .lineLimit(1)
                    .privacySensitive()
                if let advisory = next.advisory {
                    Label(advisory, systemImage: "exclamationmark.triangle.fill")
                        .lineLimit(1)
                } else {
                    Text(next.place).lineLimit(1).privacySensitive()
                }
            } else {
                Text(snapshot?.tripName ?? "RoamPulse").font(.headline).widgetAccentable()
                Text(subtitle ?? "No trip planned").lineLimit(2)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var inline: some View {
        Group {
            if let next = nextStop {
                Label("\(Self.time(next.start)) \(next.title)",
                      systemImage: next.advisory == nil ? "mappin" : "exclamationmark.triangle")
            } else {
                Label(subtitle ?? "No trip planned", systemImage: "suitcase")
            }
        }
        .privacySensitive()
    }

    private var nextStop: WidgetSnapshot.Stop? {
        switch state {
        case .active(_, let next), .upcoming(_, let next): next
        default: nil
        }
    }

    // "Next · 14:00", "Tomorrow · 08:00" or "Day 3 · 08:00"
    private func whenText(for stop: WidgetSnapshot.Stop) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: stop.start)).day ?? 0
        let prefix = switch days {
        case 0: "Next"
        case 1: "Tomorrow"
        default: "Day \(stop.day)"
        }
        return "\(prefix) · \(Self.time(stop.start))"
    }

    // 24-hour clock like the rest of the app
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
}

// For widget previews and the gallery before the app has written anything
extension WidgetSnapshot {
    static func sample(now: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        let today = calendar.startOfDay(for: now)
        func at(_ hours: Double, dayOffset: Int = 0) -> Date {
            (calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today).addingTimeInterval(hours * 3600)
        }
        // Later today, whatever time the gallery is opened
        let next = now < at(15) ? at(15) : now.addingTimeInterval(45 * 60)
        return WidgetSnapshot(
            tripID: UUID(), tripName: "Hill Country Explorer", place: "Ella",
            firstDay: calendar.date(byAdding: .day, value: -1, to: today) ?? today, dayCount: 4,
            stops: [
                Stop(id: UUID(), title: "Ravana Falls", place: "Ella", start: next, day: 2,
                     advisory: "Rain likely 12:00–18:00"),
                Stop(id: UUID(), title: "Little Adam's Peak sunrise", place: "Ella", start: at(5.5, dayOffset: 1), day: 3),
            ],
            forecast: [Forecast(start: at(0), end: at(24), temperature: 17, symbol: "cloud.drizzle.fill",
                                condition: "Light rain")]
        )
    }
}
