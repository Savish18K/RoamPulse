import SwiftUI
import WidgetKit

struct NextStopEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    // Helps the Smart Stack: a stop with a weather warning, or one coming up soon, matters more
    var relevance: TimelineEntryRelevance? {
        guard case .active(_, let next?) = snapshot?.state(at: date) else { return TimelineEntryRelevance(score: 0) }
        if next.advisory != nil { return TimelineEntryRelevance(score: 1) }
        return TimelineEntryRelevance(score: next.start.timeIntervalSince(date) < 2 * 3600 ? 0.8 : 0.4)
    }
}

// Reads what the app saved and makes an entry for each moment the widget should change
struct NextStopProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextStopEntry {
        NextStopEntry(date: .now, snapshot: .sample(now: .now))
    }

    // The widget gallery shows a sample until the app has saved a real trip
    func getSnapshot(in context: Context, completion: @escaping (NextStopEntry) -> Void) {
        let saved = WidgetSnapshot.load()
        completion(NextStopEntry(date: .now, snapshot: context.isPreview ? saved ?? .sample(now: .now) : saved))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextStopEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshot.load()
        let dates = [now] + (snapshot?.refreshDates(after: now) ?? [])
        let entries = dates.map { NextStopEntry(date: $0, snapshot: snapshot) }
        // The app reloads it whenever the plan changes, this is only in case it isn't opened for a while
        let recheck = Calendar.current.date(byAdding: .hour, value: 6, to: dates.last ?? now) ?? now
        completion(Timeline(entries: entries, policy: .after(recheck)))
    }
}

struct NextStopEntryView: View {
    let entry: NextStopEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        NextStopView(snapshot: entry.snapshot, date: entry.date, family: family)
            .containerBackground(for: .widget) { NextStopView.background }
            .widgetURL(entry.snapshot.map { WidgetLink.trip($0.tripID).url })
    }
}

struct NextStopWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: NextStopProvider()) { entry in
            NextStopEntryView(entry: entry)
        }
        .configurationDisplayName("Next Stop")
        .description("Your next planned stop and any weather warning for it.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct RoamPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextStopWidget()
    }
}

#Preview(as: .systemSmall) {
    NextStopWidget()
} timeline: {
    NextStopEntry(date: .now, snapshot: .sample(now: .now))
    NextStopEntry(date: .now, snapshot: nil)
}

#Preview(as: .systemMedium) {
    NextStopWidget()
} timeline: {
    NextStopEntry(date: .now, snapshot: .sample(now: .now))
}

#Preview(as: .accessoryRectangular) {
    NextStopWidget()
} timeline: {
    NextStopEntry(date: .now, snapshot: .sample(now: .now))
}
