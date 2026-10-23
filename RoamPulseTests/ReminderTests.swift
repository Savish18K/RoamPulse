import Foundation
import Testing
@testable import RoamPulse

/// Which reminders are planned (`ReminderPlanner`) and how `ReminderService` keeps the scheduled
/// notifications in step with the trips, using a fake notification centre.
@MainActor
struct ReminderTests {
    /// Sunday 13 December 2026, 16:40.
    let now = Calendar.trip.date(2026, 12, 13, 16, 40)
    let calendar = Calendar.trip

    /// Starts on Wednesday 16 December, with one activity on Day 1 at 09:00.
    private func upcomingTrip() -> Trip {
        var trip = Trip(name: "Southern Coast", destination: "Galle", startDate: calendar.date(2026, 12, 16),
                        endDate: calendar.date(2026, 12, 17), budget: 0, members: [], cover: .galleFort)
        trip.packing = [PackingItem(name: "Passport", category: "Documents", isPacked: true),
                        PackingItem(name: "Sunscreen", category: "Toiletries")]
        trip.activities = [Activity(day: 1, title: "Galle Fort walk", minutes: 9 * 60, place: "Galle Fort",
                                    effort: .low, isOutdoor: true)]
        return trip
    }

    // MARK: - Planner

    @Test func thePackingReminderComesTheEveningBefore() throws {
        let reminder = try #require(ReminderPlanner.packingReminder(for: upcomingTrip(), settings: ReminderSettings(), now: now))
        #expect(reminder.fireDate == calendar.date(2026, 12, 15, 19, 0))
        #expect(reminder.body.contains("1 of 2 items still to pack"))

        var settings = ReminderSettings()
        settings.packingTime = 21 * 60
        #expect(ReminderPlanner.packingReminder(for: upcomingTrip(), settings: settings, now: now)?.fireDate
                == calendar.date(2026, 12, 15, 21, 0))
    }

    @Test func activitiesAreRemindedBeforeTheyStart() throws {
        var settings = ReminderSettings()
        settings.minutesBefore = 60
        let trip = upcomingTrip()
        let reminders = ReminderPlanner.activityReminders(for: trip, settings: settings, now: now)
        let walk = try #require(reminders.first)
        #expect(walk.fireDate == calendar.date(2026, 12, 16, 8, 0))
        #expect(walk.title == "Galle Fort walk")
        #expect(walk.body.contains("in 1 h"))
        #expect(walk.id == ReminderPlanner.activityID(trip.activities[0].id), "one id per activity")
    }

    @Test func finishedPastAndSwitchedOffRemindersAreLeftOut() {
        var done = upcomingTrip()
        done.activities[0].isDone = true
        #expect(ReminderPlanner.activityReminders(for: done, settings: ReminderSettings(), now: now).isEmpty)

        let lateAtNight = calendar.date(2026, 12, 16, 10, 0)
        #expect(ReminderPlanner.plan(trips: [upcomingTrip()], settings: ReminderSettings(), now: lateAtNight).isEmpty,
                "both times have passed")

        var quiet = upcomingTrip()
        quiet.remindersOn = false
        #expect(ReminderPlanner.plan(trips: [quiet], settings: ReminderSettings(), now: now).isEmpty)

        var off = ReminderSettings()
        off.tripReminders = false
        #expect(ReminderPlanner.plan(trips: [upcomingTrip()], settings: off, now: now).isEmpty)
    }

    @Test func thePlanIsSoonestFirstAndStaysUnderTheSystemLimit() {
        var busy = upcomingTrip()
        busy.activities = (0..<80).map { index in
            Activity(day: 1 + index / 40, title: "Stop \(index)", minutes: 6 * 60 + (index % 40) * 15, place: "", effort: .low)
        }
        let plan = ReminderPlanner.plan(trips: [busy], settings: ReminderSettings(), now: now)
        #expect(plan.count == ReminderPlanner.maxScheduled)
        #expect(plan.map(\.fireDate) == plan.map(\.fireDate).sorted())
        #expect(plan.first?.id == ReminderPlanner.packingID(busy.id))
    }

    @Test func weatherAlertsAreOnlyForTodayAndTomorrowAndOnlyOnce() {
        var trip = upcomingTrip()
        trip.startDate = calendar.date(2026, 12, 13)
        trip.activities = [
            Activity(day: 2, title: "Ravana Falls", minutes: 15 * 60, place: "", effort: .moderate, isOutdoor: true),
            Activity(day: 3, title: "Hike", minutes: 15 * 60, place: "", effort: .high, isOutdoor: true),
        ]
        let rain = [14, 15].map { day in
            ForecastSlot(start: calendar.date(2026, 12, day, 15), temperature: 20, rainChance: 90, rainMM: 5,
                         conditionCode: 502, condition: "Heavy rain", symbol: "cloud.heavyrain.fill")
        }
        let weather = WeatherSnapshot(location: "Ella", condition: "", symbol: "", temperature: 20, high: 22, low: 15,
                                      humidity: 80, windKmh: 10, rainChance: 90, sunset: "18:00", fetchedAt: now,
                                      hourly: [], daily: [], slots: rain)

        let alerts = ReminderPlanner.weatherAlerts(for: trip, snapshot: weather, now: now, alreadySent: [])
        #expect(alerts.map(\.title) == ["Heavy rain likely • Tomorrow"], "the hike is the day after tomorrow")
        #expect(ReminderPlanner.weatherAlerts(for: trip, snapshot: weather, now: now, alreadySent: Set(alerts.map(\.id))).isEmpty)
    }

    // MARK: - Service

    private func makeService(permission: NotificationPermission = .allowed)
        -> (ReminderService, FakeNotificationScheduler, UserDefaults) {
        let scheduler = FakeNotificationScheduler()
        scheduler.currentPermission = permission
        let defaults = UserDefaults(suiteName: "ReminderTests-\(UUID())")!
        return (ReminderService(scheduler: scheduler, defaults: defaults, clock: FixedClock(now: now)), scheduler, defaults)
    }

    @Test func nothingIsScheduledOrAskedWithoutPermission() async {
        let (service, scheduler, _) = makeService(permission: .notDetermined)
        await service.reschedule(trips: [upcomingTrip()])
        #expect(scheduler.pending.isEmpty)
        #expect(scheduler.permissionRequests == 0, "only asked when the user turns a reminder on")
    }

    @Test func permissionIsAskedOnce() async {
        let (service, scheduler, _) = makeService(permission: .notDetermined)
        #expect(await service.requestPermissionIfNeeded())
        #expect(await service.requestPermissionIfNeeded())
        #expect(scheduler.permissionRequests == 1)
        #expect(service.permission == .allowed)
    }

    @Test func editingADeletingAnActivityUpdatesItsReminder() async throws {
        let (service, scheduler, _) = makeService()
        var trip = upcomingTrip()
        await service.reschedule(trips: [trip])
        #expect(scheduler.pending.count == 2, "packing + the walk")

        trip.activities[0].minutes = 10 * 60
        await service.reschedule(trips: [trip])
        let walk = try #require(scheduler.pending[ReminderPlanner.activityID(trip.activities[0].id)])
        #expect(walk.fireDate == calendar.date(2026, 12, 16, 9, 30), "replaced, not added twice")
        #expect(scheduler.pending.count == 2)

        trip.activities = []
        await service.reschedule(trips: [trip])
        #expect(scheduler.pending.keys.sorted() == [ReminderPlanner.packingID(trip.id)])

        await service.reschedule(trips: [])
        #expect(scheduler.pending.isEmpty, "a deleted trip's reminders are cancelled")
    }

    @Test func signingOutRemovesEveryReminder() async {
        let (service, scheduler, _) = makeService()
        await service.reschedule(trips: [upcomingTrip()])
        await service.removeAll()
        #expect(scheduler.pending.isEmpty)
    }

    @Test func settingsAreRemembered() {
        let (service, _, defaults) = makeService()
        service.settings.minutesBefore = 15
        service.settings.weatherAlerts = false
        let reloaded = ReminderSettings(defaults: defaults)
        #expect(reloaded.minutesBefore == 15)
        #expect(!reloaded.weatherAlerts)
    }
}

/// The app lock: when it locks, turning it on and off, and unlocking, with a fake Face ID.
@MainActor
struct AppLockTests {
    let start = Calendar.trip.date(2026, 12, 13, 16, 40)

    private func makeLock(enabled: Bool = false, delay: Int = 0) -> (AppLock, FakeAuthenticator, MutableClock) {
        let defaults = UserDefaults(suiteName: "AppLockTests-\(UUID())")!
        defaults.set(enabled, forKey: "appLockEnabled")
        defaults.set(delay, forKey: "lockDelayMinutes")
        let authenticator = FakeAuthenticator()
        let clock = MutableClock(start)
        return (AppLock(authenticator: authenticator, clock: clock, defaults: defaults), authenticator, clock)
    }

    @Test func itOnlyLocksWhenTurnedOn() {
        let (off, _, _) = makeLock(enabled: false)
        off.lockOnLaunch()
        #expect(!off.isLocked)

        let (on, _, _) = makeLock(enabled: true)
        on.lockOnLaunch()
        #expect(on.isLocked)
    }

    @Test func turningItOnNeedsFaceIDFirst() async {
        let (lock, authenticator, _) = makeLock()
        authenticator.nextError = .failed("Face not recognised")
        #expect(await !lock.setEnabled(true))
        #expect(!lock.isEnabled)
        #expect(lock.errorMessage == "Face not recognised")

        #expect(await lock.setEnabled(true))
        #expect(lock.isEnabled)
        #expect(authenticator.attempts == 2)
    }

    @Test func withoutAPasscodeItCantBeTurnedOn() async {
        let (lock, authenticator, _) = makeLock()
        authenticator.hasPasscode = false
        #expect(await !lock.setEnabled(true))
        #expect(lock.errorMessage == AppLockError.noPasscode.errorDescription)
        #expect(authenticator.attempts == 0)
    }

    @Test func itLocksAfterTheChosenTimeInTheBackground() {
        let (lock, _, clock) = makeLock(enabled: true, delay: 5)
        lock.didEnterBackground()
        clock.advance(minutes: 4)
        lock.didBecomeActive()
        #expect(!lock.isLocked, "back within 5 minutes")

        lock.didEnterBackground()
        clock.advance(minutes: 5)
        lock.didBecomeActive()
        #expect(lock.isLocked)
    }

    @Test func unlockingNeedsFaceIDAndCancellingIsNotAnError() async {
        let (lock, authenticator, _) = makeLock(enabled: true)
        lock.lockOnLaunch()

        authenticator.nextError = .cancelled
        await lock.unlock()
        #expect(lock.isLocked)
        #expect(lock.errorMessage == nil)

        await lock.unlock()
        #expect(!lock.isLocked)
    }

    @Test func signingOutRemovesTheLockScreen() {
        let (lock, _, _) = makeLock(enabled: true)
        lock.lockOnLaunch()
        lock.reset()
        #expect(!lock.isLocked)
    }
}
