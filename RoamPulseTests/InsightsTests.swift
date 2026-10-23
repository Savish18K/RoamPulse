import Foundation
import Testing
@testable import RoamPulse

/// Insights (search, suggestions, timeline, mood), the Statistics numbers (`TravelStats`)
/// and the Home dashboard's states.
@MainActor
struct InsightsTests {
    /// Sunday 13 December 2026, 16:40.
    let now = Calendar.trip.date(2026, 12, 13, 16, 40)
    let calendar = Calendar.trip
    let suu = Member(name: "Suu", colorHex: 1)

    private func trip(_ name: String, from start: Date, days: Int, budget: Double = 0) -> Trip {
        Trip(name: name, destination: name, startDate: start,
             endDate: calendar.date(byAdding: .day, value: days - 1, to: start) ?? start,
             budget: budget, members: [Member(name: "Me", colorHex: 0, isMe: true), suu], cover: .mistyHills)
    }

    private func memory(_ title: String, in trip: Trip, at date: Date, text: String = "", place: String = "Ella",
                        mood: Mood? = nil, sentiment: Double? = nil, people: [Member] = [], landmark: String? = nil) -> Memory {
        Memory(tripID: trip.id, title: title, date: date, day: 1, place: place, transcript: text, duration: 0,
               people: people, mood: mood, sentiment: sentiment, landmark: landmark)
    }

    @Test func searchLooksAtTextPlacesPeopleAndLandmarks() {
        let ella = trip("Ella", from: now, days: 3)
        let train = memory("Blue train", in: ella, at: now, text: "It crossed the bridge right on time.",
                           people: [suu], landmark: "Nine Arch Bridge")
        #expect(MemorySearch.matches(train, "CROSSED"), "case doesn't matter")
        #expect(MemorySearch.matches(train, "suu"))
        #expect(MemorySearch.matches(train, "nine arch"))
        #expect(MemorySearch.matches(train, "ella"), "the place")
        #expect(!MemorySearch.matches(train, "temple"))
    }

    @Test func theSnippetIsTheSentenceThatMatches() {
        let text = "The mist cleared. Tea pluckers worked on the terraces. Then it rained!"
        #expect(MemorySearch.snippet(of: text, matching: "tea") == "… Tea pluckers worked on the terraces.")
        #expect(MemorySearch.snippet(of: text, matching: "mist") == "The mist cleared.")
        #expect(MemorySearch.snippet(of: text, matching: "Suu") == text, "matched elsewhere: the start of the text")
    }

    @Test func suggestionsAreThePlacesAndPeopleMentionedMost() {
        let ella = trip("Ella", from: now, days: 3)
        let memories = [
            memory("A", in: ella, at: now, place: "Ella", people: [suu]),
            memory("B", in: ella, at: now, place: "Ella", people: [suu]),
            memory("C", in: ella, at: now, place: "Kandy"),
        ]
        #expect(MemorySearch.suggestions(from: memories) == ["Ella", "Suu", "Kandy"])
    }

    @Test func aPlaceTappedOnAMemoryOpensTheSearch() {
        let router = AppRouter()
        router.activeSheet = .memory(UUID())
        router.searchInsights(for: "Ella")
        #expect(router.selectedTab == .insights)
        #expect(router.insightsSearch == "Ella")
        #expect(router.activeSheet == nil)
    }

    @Test func theTimelineGroupsByDayNewestFirst() {
        let ella = trip("Hill Country", from: calendar.date(2026, 12, 12), days: 4)
        let store = TripStore(repository: InMemoryTripRepository(trips: [ella]), clock: FixedClock(now: now))
        store.addMemory(memory("Breakfast", in: ella, at: calendar.date(2026, 12, 13, 8)))
        store.addMemory(memory("Train", in: ella, at: calendar.date(2026, 12, 13, 11)))
        store.addMemory(memory("Temple", in: ella, at: calendar.date(2026, 12, 12, 11)))

        let timeline = InsightsViewModel(store: store).timeline
        #expect(timeline.map { $0.memories.map(\.title) } == [["Breakfast", "Train"], ["Temple"]])
        #expect(timeline.first?.title.contains("Hill Country") == true)
    }

    @Test func eachDaysMoodIsTheAverageOfItsMemories() {
        let ella = trip("Ella", from: calendar.date(2026, 12, 12), days: 4)
        let store = TripStore(repository: InMemoryTripRepository(trips: [ella]), clock: FixedClock(now: now))
        store.addMemory(memory("Read", in: ella, at: calendar.date(2026, 12, 12, 9), mood: .positive, sentiment: 0.8))
        store.addMemory(memory("Picked", in: ella, at: calendar.date(2026, 12, 12, 18), mood: .negative))
        store.addMemory(memory("No mood", in: ella, at: calendar.date(2026, 12, 13, 9)))

        let insights = InsightsViewModel(store: store)
        #expect(insights.dayMoods.count == 1, "days without a mood are left out")
        #expect(abs((insights.dayMoods.first?.score ?? 0) - 0.1) < 0.0001, "(0.8 + -0.6) / 2")
        #expect(insights.dayMoods.first?.mood == .mixed)
        #expect(insights.count(of: .negative) == 1)
        #expect(MemorySearch.moodScore(store.memories[2]) == nil)
    }

    @Test func statisticsCountTripsThatHaveStarted() {
        let finished = trip("Colombo", from: calendar.date(2026, 10, 3), days: 2, budget: 50_000)
        let active = trip("Ella", from: calendar.date(2026, 12, 12), days: 4, budget: 10_000)
        let lastYear = trip("Galle", from: calendar.date(2025, 6, 1), days: 3)
        let upcoming = trip("Jaffna", from: calendar.date(2027, 4, 10), days: 5)
        var spender = finished
        spender.expenses = [Expense(title: "Hotel", amount: 30_000, category: .lodging, paidBy: spender.members[0],
                                    shares: [], date: finished.startDate)]
        var overspent = active
        overspent.expenses = [Expense(title: "Train", amount: 12_000, category: .transport, paidBy: active.members[0],
                                      shares: [], date: active.startDate)]
        let memories = [memory("Bridge", in: overspent, at: now, landmark: "Nine Arch Bridge"),
                        memory("Bridge again", in: overspent, at: now, landmark: "Nine Arch Bridge")]
        let all = [spender, overspent, lastYear, upcoming]

        let year = TravelStats.make(trips: all, memories: memories, now: now, period: .year(2026))
        #expect(year.trips.map(\.name) == ["Colombo", "Ella"], "not last year's, not the upcoming one")
        #expect(year.daysTravelled == 2 + 2, "the active trip counts the days so far")
        #expect(year.totalSpent == 42_000)
        #expect(year.byCategory[.lodging] == 30_000)
        #expect(year.averagePerDay == 10_500)
        #expect(year.memories == 2)
        #expect(year.landmarks == ["Nine Arch Bridge"], "each landmark once")
        #expect(year.isOnBudget, "42,000 of 60,000 across the budgeted trips")

        let allTime = TravelStats.make(trips: all, memories: memories, now: now, period: .allTime)
        #expect(allTime.tripCount == 3)
        #expect(TravelStats.make(trips: [upcoming], memories: [], now: now, period: .allTime).isEmpty)
    }

    private func home(_ trips: [Trip]) -> HomeViewModel {
        let clock = FixedClock(now: now)
        let store = TripStore(repository: InMemoryTripRepository(trips: trips), clock: clock)
        return HomeViewModel(store: store, clock: clock, weather: MockWeatherService(clock: clock))
    }

    @Test func homeShowsTheMostUsefulState() {
        let active = trip("Ella", from: calendar.date(2026, 12, 12), days: 4)
        let upcoming = trip("Jaffna", from: calendar.date(2027, 4, 10), days: 5)
        let finished = trip("Colombo", from: calendar.date(2026, 10, 3), days: 2)

        #expect(home([]).state == .noTrips)
        #expect(home([finished]).state == .completed(finished.id))
        #expect(home([finished, upcoming]).state == .upcoming(upcoming.id))
        #expect(home([finished, upcoming, active]).state == .active(active.id))
    }

    @Test func beforeATripHomeSaysWhatIsLeftToDo() {
        var soon = trip("Galle", from: calendar.date(2026, 12, 20), days: 2, budget: 40_000)
        soon.packing = [PackingItem(name: "Passport", category: "Documents", isPacked: true),
                        PackingItem(name: "Sunscreen", category: "Toiletries")]
        soon.activities = [Activity(day: 1, title: "Fort walk", minutes: 540, place: "Galle", effort: .low)]
        let home = home([soon])

        let items = Dictionary(uniqueKeysWithValues: home.readiness(for: soon).map { ($0.id, $0) })
        #expect(items["packing"]?.detail == "1 of 2 packed")
        #expect(items["packing"]?.isDone == false)
        #expect(items["plan"]?.detail == "1 activities over 1 of 2 days")
        #expect(items["budget"]?.isDone == true)
        #expect(items["people"]?.isDone == true, "Suu is coming")
        #expect(home.countdownText(for: soon) == "In 7 days")
        #expect(!home.forecastIsAvailable(for: soon), "more than 5 days away")
        #expect(home.forecastNote(for: soon).contains("Wed 16 Dec"))
    }

    @Test func aFailedForecastIsExplainedInsteadOfSpinningForever() async {
        let active = trip("Ella", from: calendar.date(2026, 12, 12), days: 4)
        let clock = FixedClock(now: now)
        let store = TripStore(repository: InMemoryTripRepository(trips: [active]), clock: clock)
        let http = FakeHTTPClient()
        http.error = URLError(.notConnectedToInternet)
        let weather = OpenWeatherMapService(client: OpenWeatherMapClient(apiKey: "test", http: http), clock: clock)
        weather.store = store
        let home = HomeViewModel(store: store, clock: clock, weather: weather)

        await home.loadWeather()
        #expect(home.weather == nil)
        #expect(home.weatherError == WeatherError.offline.errorDescription)
        #expect(!home.isLoadingWeather)
    }
}
