import Foundation
import Testing
@testable import RoamPulse

/// Trip status and sorting, the store, and the view models, using an in-memory repository
/// and a fixed clock instead of Core Data and the real time.
@MainActor
struct TripStoreTests {
    /// Sunday 13 December 2026, 16:40, like the prototype.
    let now = Calendar.trip.date(2026, 12, 13, 16, 40)
    let me = Member(name: "Savishka", colorHex: 0, isMe: true)
    let samee = Member(name: "Samee", colorHex: 0)

    private func trip(_ name: String, startsIn offset: Int, days: Int) -> Trip {
        let calendar = Calendar.trip
        let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
        let end = calendar.date(byAdding: .day, value: days - 1, to: start) ?? start
        return Trip(name: name, destination: "Ella", startDate: start, endDate: end, budget: 10_000,
                    members: [me, samee], cover: .mistyHills)
    }

    private func makeStore(_ trips: [Trip] = [], repository: InMemoryTripRepository? = nil) -> TripStore {
        TripStore(repository: repository ?? InMemoryTripRepository(trips: trips), clock: FixedClock(now: now))
    }

    // MARK: - Status and sorting

    @Test func tripsAreSortedIntoActiveUpcomingAndCompleted() {
        let trips = [
            trip("Later", startsIn: 60, days: 3),
            trip("Old", startsIn: -30, days: 3),
            trip("Now", startsIn: -1, days: 4),
            trip("Soon", startsIn: 5, days: 2),
            trip("Recent", startsIn: -10, days: 2),
        ]
        let sections = trips.sections(at: now)
        #expect(sections.active.map(\.name) == ["Now"])
        #expect(sections.upcoming.map(\.name) == ["Soon", "Later"])
        #expect(sections.completed.map(\.name) == ["Recent", "Old"])
    }

    @Test func statusAndDayNumberAtTheEdgesOfATrip() {
        let ella = trip("Ella", startsIn: -1, days: 4) // yesterday to two days from now
        let calendar = Calendar.trip

        #expect(ella.status(at: now) == .active)
        #expect(ella.dayNumber(at: now) == 2)
        #expect(ella.statusText(at: now) == "Active • Day 2 of 4")

        let lastDayLate = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: ella.endDate)!
        #expect(ella.status(at: lastDayLate) == .active)

        let dayAfter = calendar.date(byAdding: .day, value: 1, to: ella.endDate)!
        #expect(ella.status(at: dayAfter) == .completed)
        #expect(ella.dayNumber(at: dayAfter) == nil)

        let dayBefore = calendar.date(byAdding: .day, value: -1, to: ella.startDate)!
        #expect(ella.status(at: dayBefore) == .upcoming)
    }

    @Test func anEndDateBeforeTheStartStillCountsAsOneDay() {
        var broken = trip("Broken", startsIn: 3, days: 1)
        broken.endDate = Calendar.trip.date(byAdding: .day, value: -2, to: broken.startDate)!
        #expect(broken.dayCount == 1)
    }

    // MARK: - Store

    @Test func anAddedTripIsSaved() {
        let repository = InMemoryTripRepository()
        let store = makeStore(repository: repository)
        store.addTrip(trip("Galle", startsIn: 7, days: 3))

        // A new store reading the same repository is like reopening the app.
        let reopened = makeStore(repository: repository)
        #expect(reopened.trips.map(\.name) == ["Galle"])
    }

    @Test func aFailedSaveKeepsTheOldValueAndShowsAnError() {
        let original = trip("Old name", startsIn: 7, days: 3)
        let repository = InMemoryTripRepository(trips: [original])
        let store = makeStore(repository: repository)

        repository.failSaves = true
        let saved = store.updateTrip(original.id) { $0.name = "New name" }

        #expect(saved == false)
        #expect(store.trip(original.id)?.name == "Old name")
        #expect(store.errorMessage != nil)
    }

    @Test func deletingATripAlsoDeletesItsMemories() {
        let ella = trip("Ella", startsIn: -1, days: 4)
        let memory = Memory(tripID: ella.id, title: "Blue train", date: now, day: 2, place: "Ella",
                            transcript: "", duration: 30, people: [])
        let store = TripStore(repository: InMemoryTripRepository(trips: [ella], memories: [memory]),
                              clock: FixedClock(now: now))

        store.deleteTrip(ella.id)

        #expect(store.trips.isEmpty)
        #expect(store.memories.isEmpty)
    }

    // MARK: - Trip form

    @Test func creatingATripAddsTheDefaultPackingListAndYou() throws {
        let store = makeStore()
        let form = TripFormViewModel(store: store, clock: FixedClock(now: now))
        form.name = "Southern Coast Weekend"
        form.destination = "Galle"

        #expect(form.save())
        let created = try #require(store.trips.first)
        #expect(created.packing.count == PackingAdvisor.defaultTemplate().count)
        #expect(created.members.contains { $0.isMe })
        #expect(created.cover == .galleFort)
    }

    @Test func theFormRejectsAnEndDateBeforeTheStart() {
        let form = TripFormViewModel(store: makeStore(), clock: FixedClock(now: now))
        form.name = "Backwards"
        form.destination = "Kandy"
        form.endDate = Calendar.trip.date(byAdding: .day, value: -1, to: form.startDate)!

        #expect(form.datesAreValid == false)
        #expect(form.canSave == false)
        #expect(form.save() == false)
    }

    @Test func shorteningATripMovesActivitiesFromRemovedDays() {
        var ella = trip("Ella", startsIn: 7, days: 4)
        ella.activities = [Activity(day: 4, title: "Tea factory", minutes: 540, place: "Ella", effort: .low)]
        let store = makeStore([ella])
        let form = TripFormViewModel(tripID: ella.id, store: store, clock: FixedClock(now: now))

        form.endDate = Calendar.trip.date(byAdding: .day, value: 1, to: form.startDate)! // now 2 days
        #expect(form.shortenedTripWarning != nil)
        #expect(form.save())
        #expect(store.trip(ella.id)?.activities.first?.day == 2)
    }

    @Test func youCannotRemoveSomeoneWhoHasExpenses() {
        var ella = trip("Ella", startsIn: 7, days: 4)
        ella.expenses = [Expense(title: "Taxi", amount: 1_000, category: .transport, paidBy: samee,
                                 shares: ExpenseCalculator.equalShares(of: 1_000, between: [me, samee]), date: now)]
        let form = TripFormViewModel(tripID: ella.id, store: makeStore([ella]), clock: FixedClock(now: now))

        #expect(form.canRemove(samee) == false)
        #expect(form.canRemove(me) == false)
    }

    // MARK: - Itinerary view model

    @Test func draggingAnActivityOntoAnotherReordersTheDay() {
        var ella = trip("Ella", startsIn: -2, days: 4) // today is Day 3
        let hike = Activity(day: 3, title: "Hike", minutes: 360, place: "Ella", effort: .high)
        let falls = Activity(day: 3, title: "Falls", minutes: 900, place: "Ella", effort: .moderate)
        ella.activities = [hike, falls]
        let store = makeStore([ella])
        let detail = TripDetailViewModel(tripID: ella.id, store: store, clock: FixedClock(now: now),
                                         weather: MockWeatherService(clock: FixedClock(now: now)))

        #expect(detail.selectedDay == 3)
        #expect(detail.moveActivity(falls.id, onto: hike))
        #expect(detail.activities.map(\.title) == ["Falls", "Hike"])
        #expect(detail.activities.map(\.timeText) == ["06:00", "15:00"])
    }

    @Test func droppingAnActivityOnADayTabMovesIt() {
        var ella = trip("Ella", startsIn: -2, days: 4)
        let falls = Activity(day: 3, title: "Falls", minutes: 900, place: "Ella", effort: .moderate)
        ella.activities = [falls]
        let store = makeStore([ella])
        let detail = TripDetailViewModel(tripID: ella.id, store: store, clock: FixedClock(now: now),
                                         weather: MockWeatherService(clock: FixedClock(now: now)))

        #expect(detail.moveActivity(falls.id, toDayIndex: 3)) // the "Day 4" tab
        #expect(store.trip(ella.id)?.activities.first?.day == 4)
    }

    // MARK: - Expense view models

    @Test func settlingUpRecordsPaymentsUntilNobodyOwes() {
        var ella = trip("Ella", startsIn: -1, days: 4)
        ella.expenses = [Expense(title: "Homestay", amount: 18_000, category: .lodging, paidBy: me,
                                 shares: ExpenseCalculator.equalShares(of: 18_000, between: [me, samee]), date: now)]
        let store = makeStore([ella])
        let analytics = ExpenseAnalyticsViewModel(tripID: ella.id, store: store, clock: FixedClock(now: now))

        #expect(analytics.settlements.count == 1)
        analytics.settle(analytics.settlements[0])

        #expect(analytics.settlements.isEmpty)
        #expect(analytics.payments.count == 1)
        #expect(analytics.payments.first?.amount == 9_000)
    }

    @Test func aCustomSplitHasToAddUpBeforeItCanBeSaved() throws {
        let ella = trip("Ella", startsIn: -1, days: 4)
        let store = makeStore([ella])
        let form = ExpenseFormViewModel(tripID: ella.id, store: store, clock: FixedClock(now: now))

        for key in ["1", "0", "0", "0"] { form.press(key) }
        form.setSplitMethod(.custom) // starts as an equal split: 500 + 500
        #expect(form.unassigned == 0)
        #expect(form.canSave)

        form.activeField = .share(me.id)
        form.press(AmountInput.deleteKey) // 500 → 50
        #expect(form.unassigned == 450)
        #expect(form.canSave == false)
        #expect(form.validationMessage != nil)

        for key in ["0", "0"] { form.press(key) } // 50 → 5000, now too much
        #expect(form.unassigned == -4_500)

        form.press(AmountInput.deleteKey) // back to 500
        #expect(form.save())
        let saved = try #require(store.trip(ella.id)?.expenses.first)
        #expect(saved.splitMethod == .custom)
        #expect(saved.shares.map(\.amount) == [500, 500])
    }

    @Test func theNumberPadAllowsOnlyTwoDecimalPlaces() {
        var text = ""
        for key in ["0", ".", "5", "5", "5"] { text = AmountInput.apply(key, to: text) }
        #expect(text == "0.55")
        #expect(AmountInput.apply(".", to: "12.5") == "12.5")
        #expect(AmountInput.apply("7", to: "0") == "7")
    }
}
