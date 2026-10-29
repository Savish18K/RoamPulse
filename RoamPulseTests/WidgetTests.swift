import Foundation
import SwiftUI
import Testing
import WidgetKit
@testable import RoamPulse

// The Home Screen widget: which trip and stops it gets, its timeline and its links
@MainActor
struct WidgetTests {
    // Sun 13 Dec 2026, 16:40 (day 2 of the trip below)
    let now = Calendar.trip.date(2026, 12, 13, 16, 40)
    let trip: Trip

    init() {
        var trip = Trip(name: "Hill Country", destination: "Kandy to Ella", startDate: Calendar.trip.date(2026, 12, 12),
                        endDate: Calendar.trip.date(2026, 12, 15), budget: 0, members: [SampleData.me], cover: .hillTrain)
        trip.activities = [
            Activity(day: 1, title: "Temple of the Tooth", minutes: 11 * 60, place: "Kandy", effort: .low),
            Activity(day: 2, title: "Nine Arch Bridge viewpoint", minutes: 17 * 60 + 30, place: "Nine Arch Bridge",
                     effort: .moderate, isOutdoor: true),
            Activity(day: 2, title: "Check in", minutes: 16 * 60, place: "Ella", effort: .low, isDone: true),
            Activity(day: 3, title: "Little Adam's Peak", minutes: 6 * 60, place: "Little Adam's Peak", effort: .high),
            Activity(day: 3, title: "Ella spice garden", minutes: 11 * 60, place: "Ella", effort: .low),
            Activity(day: 4, title: "Tea factory tour", minutes: 9 * 60, place: "Halpewatte", effort: .low),
        ]
        self.trip = trip
    }

    private func trip(startingInDays days: Int, name: String) -> Trip {
        let start = Calendar.trip.date(byAdding: .day, value: days, to: Calendar.trip.startOfDay(for: now))!
        return Trip(name: name, destination: "Galle", startDate: start,
                    endDate: Calendar.trip.date(byAdding: .day, value: 2, to: start)!, budget: 0,
                    members: [SampleData.me], cover: .galleFort)
    }

    @Test func onlyStopsStillToComeAreSentInTimeOrder() {
        let snapshot = WidgetPlanner.snapshot(for: trip, forecast: nil, now: now)

        // Day 1 is over and check in is done
        #expect(snapshot.stops.map(\.title) == ["Nine Arch Bridge viewpoint", "Little Adam's Peak", "Ella spice garden",
                                                "Tea factory tour"])
        #expect(snapshot.stops.first?.start == Calendar.trip.date(2026, 12, 13, 17, 30))
        #expect(snapshot.place == "Ella")
        #expect(snapshot.state(at: now, calendar: .trip) == .active(day: 2, next: snapshot.stops.first))
    }

    @Test func outdoorStopsGetTheSameWeatherWarningAsTheApp() async throws {
        let forecast = try await MockWeatherService(clock: FixedClock(now: now)).forecast(for: trip)
        let snapshot = WidgetPlanner.snapshot(for: trip, forecast: forecast, now: now)

        // Rain this afternoon, and the viewpoint is outdoors
        let viewpoint = try #require(snapshot.stops.first)
        #expect(viewpoint.advisory?.hasPrefix("Rain likely") == true)
        #expect(snapshot.stops.dropFirst().allSatisfy { $0.advisory == nil }, "indoor stops get no warning")
        #expect(snapshot.forecast(at: now) != nil, "the current forecast step is there for the weather line")
        #expect(snapshot.forecast.count <= WidgetPlanner.maxForecastSteps)
    }

    @Test func theNextStopMovesOnThroughTheTrip() {
        let snapshot = WidgetPlanner.snapshot(for: trip, forecast: nil, now: now)
        let calendar = Calendar.trip

        // The timeline redraws right at 17:30, and by then the viewpoint has started
        #expect(snapshot.nextStop(at: calendar.date(2026, 12, 13, 17, 30))?.title == "Little Adam's Peak")
        #expect(snapshot.state(at: calendar.date(2026, 12, 10, 9), calendar: calendar)
                == .upcoming(daysToGo: 2, first: snapshot.stops.first))
        #expect(snapshot.state(at: calendar.date(2026, 12, 16, 9), calendar: calendar) == .finished)
    }

    @Test func itRedrawsAsEachStopStartsAndAtMidnight() {
        let snapshot = WidgetPlanner.snapshot(for: trip, forecast: nil, now: now)
        let dates = snapshot.refreshDates(after: now, calendar: .trip)

        #expect(dates.contains(Calendar.trip.date(2026, 12, 13, 17, 30)))
        #expect(dates.contains(Calendar.trip.date(2026, 12, 14)), "day 3 starts at midnight")
        #expect(dates.contains(Calendar.trip.date(2026, 12, 16)), "the trip ends")
        #expect(dates == dates.sorted() && dates.allSatisfy { $0 > now })
        #expect(dates.allSatisfy { $0.timeIntervalSince(now) <= 7 * 24 * 3600 })
    }

    @Test func todaysTripComesFirstAndFinishedTripsAreLeftOut() {
        let soon = trip(startingInDays: 3, name: "Galle weekend")
        let later = trip(startingInDays: 30, name: "Jaffna")
        let finished = trip(startingInDays: -10, name: "Kandy")

        #expect(WidgetPlanner.featuredTrip(in: [later, soon, trip, finished], now: now)?.name == "Hill Country")
        #expect(WidgetPlanner.featuredTrip(in: [later, soon, finished], now: now)?.name == "Galle weekend")
        #expect(WidgetPlanner.featuredTrip(in: [finished], now: now) == nil)
    }

    @Test func widgetLinksOpenTheRightThing() throws {
        let id = UUID()
        #expect(WidgetLink(url: WidgetLink.trip(id).url) == .trip(id))
        #expect(WidgetLink(url: WidgetLink.recordMemory(id).url) == .recordMemory(id))
        #expect(WidgetLink(url: try #require(URL(string: "https://example.com/trip/\(id)"))) == nil)
        #expect(WidgetLink(url: try #require(URL(string: "roampulse://share/\(id)"))) == nil)
        #expect(WidgetLink(url: try #require(URL(string: "roampulse://trip/not-an-id"))) == nil)
    }

    @Test func itIsOnlyRewrittenWhenSomethingChanged() async {
        let store = FakeWidgetStore()
        let clock = FixedClock(now: now)
        let widgets = WidgetService(storage: store, weather: MockWeatherService(clock: clock), clock: clock)

        await widgets.update(trips: [trip])
        await widgets.update(trips: [trip])
        #expect(store.saves.count == 1)
        #expect(store.saves.last??.tripName == "Hill Country")

        // Signing out empties it
        widgets.clear()
        #expect(store.saves.count == 2)
        #expect(store.saves.last == .some(nil))
    }

    @Test func everySizeDrawsForEveryState() throws {
        let sizes: [(WidgetFamily, CGSize)] = [(.systemSmall, CGSize(width: 170, height: 170)),
                                               (.systemMedium, CGSize(width: 364, height: 170)),
                                               (.accessoryRectangular, CGSize(width: 172, height: 76)),
                                               (.accessoryInline, CGSize(width: 250, height: 20))]
        let active = WidgetPlanner.snapshot(for: trip, forecast: nil, now: now)
        let snapshots: [WidgetSnapshot?] = [.sample(now: .now), active, nil]

        for (family, size) in sizes {
            for snapshot in snapshots {
                let view = NextStopView(snapshot: snapshot, date: snapshot == active ? now : .now, family: family)
                    .padding(family == .systemSmall || family == .systemMedium ? 16 : 0)
                    .frame(width: size.width, height: size.height)
                    .background(NextStopView.background)
                let image = ImageRenderer(content: view).uiImage
                #expect(image.map { $0.size == size } == true, "\(family)")
            }
        }
    }
}
