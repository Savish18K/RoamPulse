import CoreLocation
import Foundation
import Testing
@testable import RoamPulse

// Geofencing, arrival alerts, the trip map and pinning activities on it
@MainActor
struct MapTests {
    // Sun 13 Dec 2026, 16:40 (day 2 of the trip below)
    let now = Calendar.trip.date(2026, 12, 13, 16, 40)
    let trip: Trip

    init() {
        var trip = Trip(name: "Hill Country", destination: "Kandy to Ella", startDate: Calendar.trip.date(2026, 12, 12),
                        endDate: Calendar.trip.date(2026, 12, 15), budget: 0, members: [SampleData.me], cover: .hillTrain)
        trip.activities = [
            Activity(day: 1, title: "Temple of the Tooth", minutes: 11 * 60, place: "Kandy", effort: .low,
                     latitude: 7.2936, longitude: 80.6413),
            Activity(day: 2, title: "Nine Arch Bridge viewpoint", minutes: 17 * 60 + 30, place: "Nine Arch Bridge",
                     effort: .moderate, latitude: 6.8768, longitude: 81.0608),
            Activity(day: 2, title: "Check in", minutes: 16 * 60, place: "Ella", effort: .low, isDone: true,
                     latitude: 6.8721, longitude: 81.0489),
            Activity(day: 3, title: "Little Adam's Peak", minutes: 6 * 60, place: "Little Adam's Peak", effort: .high,
                     latitude: 6.8656, longitude: 81.0610),
            Activity(day: 3, title: "Ella spice garden", minutes: 11 * 60, place: "Ella", effort: .low),
            Activity(day: 4, title: "Tea factory tour", minutes: 9 * 60, place: "Halpewatte", effort: .low,
                     latitude: 6.8810, longitude: 81.0290),
        ]
        self.trip = trip
    }

    private func activity(_ title: String) -> Activity {
        trip.activities.first { $0.title == title }!
    }

    @Test func todaysAndTomorrowsPlacesAreWatched() {
        let fences = GeofencePlanner.plan(trips: [trip], now: now)

        // Day 1 is over, check in is done, the spice garden isn't pinned and day 4 is too far away
        #expect(fences.map(\.title) == ["Nine Arch Bridge viewpoint", "Little Adam's Peak"])
        #expect(fences.first?.id == GeofencePlanner.id(for: activity("Nine Arch Bridge viewpoint").id))
        #expect(fences.first?.radius == GeofencePlanner.radius)
        #expect(fences.first?.start == Calendar.trip.date(2026, 12, 13, 17, 30))
    }

    @Test func tripsWithRemindersOffAreNotWatched() {
        var quiet = trip
        quiet.remindersOn = false
        #expect(GeofencePlanner.plan(trips: [quiet], now: now).isEmpty)
    }

    @Test func onlyTwentyRegionsAreWatched() {
        var busy = trip
        busy.activities = (0..<30).map { index in
            Activity(day: 2, title: "Stop \(index)", minutes: 17 * 60 + index, place: "Ella", effort: .low,
                     latitude: 6.87, longitude: 81.04)
        }
        let fences = GeofencePlanner.plan(trips: [busy], now: now)
        #expect(fences.count == GeofencePlanner.maxRegions)
        #expect(fences.first?.title == "Stop 0", "the soonest ones are kept")
    }

    @Test func arrivingAlertsOnlyOnTheDayOfTheActivity() throws {
        let fences = GeofencePlanner.plan(trips: [trip], now: now)
        let bridge = try #require(fences.first { $0.title == "Nine Arch Bridge viewpoint" })
        let peak = try #require(fences.first { $0.title == "Little Adam's Peak" })

        let alert = try #require(GeofencePlanner.arrivalAlert(for: bridge, now: now, alreadySent: []))
        #expect(alert.title == "You're at Nine Arch Bridge")
        #expect(alert.body.contains("17:30"))
        #expect(alert.activityID == bridge.activityID)
        #expect(alert.tripID == trip.id)

        #expect(GeofencePlanner.arrivalAlert(for: peak, now: now, alreadySent: []) == nil, "that's tomorrow's plan")
        #expect(GeofencePlanner.arrivalAlert(for: bridge, now: now, alreadySent: [alert.id]) == nil, "only once")
    }

    private func makeGeofences(arrivalAlerts: Bool = true, defaults: UserDefaults? = nil)
        -> (GeofenceService, FakeRegionMonitor, FakeLocationPermission, FakeNotificationScheduler, ReminderService) {
        let defaults = defaults ?? UserDefaults(suiteName: "MapTests-\(UUID())")!
        let scheduler = FakeNotificationScheduler()
        scheduler.currentPermission = .allowed
        let reminders = ReminderService(scheduler: scheduler, defaults: defaults, clock: FixedClock(now: now))
        reminders.settings.arrivalAlerts = arrivalAlerts
        let monitor = FakeRegionMonitor()
        let location = FakeLocationPermission()
        let service = GeofenceService(monitor: monitor, location: location, reminders: reminders, defaults: defaults,
                                      clock: FixedClock(now: now))
        return (service, monitor, location, scheduler, reminders)
    }

    @Test func theWatchedRegionsFollowThePlanAndTheSettings() async {
        let (service, monitor, location, _, reminders) = makeGeofences()

        await service.update(trips: [trip])
        #expect(Set(monitor.regions.keys) == Set(GeofencePlanner.plan(trips: [trip], now: now).map(\.id)))
        #expect(service.fences(for: trip.id).count == 2)

        location.canMonitorRegions = false
        await service.update(trips: [trip])
        #expect(monitor.regions.isEmpty, "no location permission, nothing is watched")

        location.canMonitorRegions = true
        reminders.settings.arrivalAlerts = false
        await service.update(trips: [trip])
        #expect(monitor.regions.isEmpty)
        #expect(service.fences.isEmpty)
    }

    @Test func movingAPlaceUpdatesItsRegion() async throws {
        let (service, monitor, _, _, _) = makeGeofences()
        await service.update(trips: [trip])
        let adds = monitor.addCount

        await service.update(trips: [trip])
        #expect(monitor.addCount == adds, "nothing changed, nothing is added again")

        var moved = trip
        let index = try #require(moved.activities.firstIndex { $0.title == "Nine Arch Bridge viewpoint" })
        moved.activities[index].latitude = 6.8800
        await service.update(trips: [moved])
        #expect(monitor.addCount == adds + 1)
        #expect(monitor.regions[GeofencePlanner.id(for: moved.activities[index].id)]?.latitude == 6.8800)
    }

    @Test func arrivingSendsOneAlertThatOpensAMemory() async throws {
        let (service, monitor, _, scheduler, _) = makeGeofences()
        await service.update(trips: [trip])
        service.start()
        let bridgeID = GeofencePlanner.id(for: activity("Nine Arch Bridge viewpoint").id)

        // Give the listener a moment to start, then walk into the region
        for _ in 0..<50 where scheduler.delivered.isEmpty {
            monitor.arrive(at: bridgeID)
            try await Task.sleep(for: .milliseconds(20))
        }
        let alert = try #require(scheduler.delivered.first)
        #expect(alert.activityID == activity("Nine Arch Bridge viewpoint").id)

        await service.handleArrival(bridgeID)
        #expect(scheduler.delivered.count == 1, "the same arrival isn't announced twice")
    }

    @Test func aNewLocationInsideAFenceCountsAsArriving() async {
        let (service, _, _, scheduler, _) = makeGeofences()
        await service.update(trips: [trip])

        // 300 m away, outside the 150 m circle
        await service.checkArrival(at: CLLocation(latitude: 6.8795, longitude: 81.0608))
        #expect(scheduler.delivered.isEmpty)

        await service.checkArrival(at: CLLocation(latitude: 6.8770, longitude: 81.0609))
        #expect(scheduler.delivered.map(\.title) == ["You're at Nine Arch Bridge"])

        // Walking around the bridge doesn't send it again
        await service.checkArrival(at: CLLocation(latitude: 6.8766, longitude: 81.0607))
        #expect(scheduler.delivered.count == 1)
    }

    @Test func noAlertWhenArrivalAlertsAreOff() async {
        let (service, _, _, scheduler, reminders) = makeGeofences()
        await service.update(trips: [trip])
        reminders.settings.arrivalAlerts = false

        await service.handleArrival(GeofencePlanner.id(for: activity("Nine Arch Bridge viewpoint").id))
        #expect(scheduler.delivered.isEmpty)
    }

    @Test func watchedPlacesAreRememberedForABackgroundLaunch() async {
        let defaults = UserDefaults(suiteName: "MapTests-\(UUID())")!
        let first = makeGeofences(defaults: defaults).0
        await first.update(trips: [trip])

        // iOS opens the app in the background for an arrival, before any trips are loaded
        let (relaunched, _, _, scheduler, _) = makeGeofences(defaults: defaults)
        #expect(relaunched.fences == first.fences)
        await relaunched.handleArrival(GeofencePlanner.id(for: activity("Nine Arch Bridge viewpoint").id))
        #expect(scheduler.delivered.count == 1)
    }

    @Test func theArrivalSettingIsSaved() {
        let defaults = UserDefaults(suiteName: "MapTests-\(UUID())")!
        #expect(ReminderSettings(defaults: defaults).arrivalAlerts == false, "off until the user turns it on")
        var settings = ReminderSettings()
        settings.arrivalAlerts = true
        settings.save(to: defaults)
        #expect(ReminderSettings(defaults: defaults).arrivalAlerts)
    }

    private func makeStore() -> TripStore {
        TripStore(repository: InMemoryTripRepository(trips: [trip]), clock: FixedClock(now: now))
    }

    @Test func theMapOpensOnTodayWithTheStopsInOrder() {
        let map = TripMapViewModel(tripID: trip.id, store: makeStore(), clock: FixedClock(now: now), places: FakePlaceSearch())

        #expect(map.selectedDay == 2)
        #expect(map.pinned.map(\.title) == ["Check in", "Nine Arch Bridge viewpoint"])
        #expect(map.pins.map(\.number) == [1, 2])
        #expect(map.dayRoute.count == 2)
        #expect(map.nextActivityID == activity("Nine Arch Bridge viewpoint").id)

        map.selectedDayIndex = 0
        #expect(map.selectedDay == nil)
        #expect(map.pinned.count == 5)
        #expect(map.pinned.first?.title == "Temple of the Tooth")
        #expect(map.dayRoute.isEmpty, "no route line across the whole trip")
        #expect(map.unpinned.map(\.title) == ["Ella spice garden"])
    }

    @Test func openingFromAnActivityShowsItsDay() {
        let peak = activity("Little Adam's Peak")
        let map = TripMapViewModel(tripID: trip.id, activityID: peak.id, store: makeStore(), clock: FixedClock(now: now),
                                   places: FakePlaceSearch())
        #expect(map.selectedDay == 3)
        #expect(map.selectedActivity?.id == peak.id)

        map.selectedDay = 2
        #expect(map.selectedActivityID == nil, "the selection is cleared when its day isn't shown")
    }

    @Test func missingPlacesAreFoundNearTheTrip() async throws {
        let store = makeStore()
        let search = FakePlaceSearch()
        // The first search finds a place in Colombo, too far away, so the place name is tried next
        search.results["Ella spice garden"] = [MapPlace(name: "Spice Garden", address: "Colombo", latitude: 6.93, longitude: 79.85)]
        search.results["Ella"] = [MapPlace(name: "Ella", address: "Badulla", latitude: 6.8693, longitude: 81.0441)]
        let map = TripMapViewModel(tripID: trip.id, store: store, clock: FixedClock(now: now), places: search)
        map.selectedDay = 3

        await map.locateMissing()

        #expect(search.queries == ["Ella spice garden", "Ella"])
        let garden = try #require(store.trip(trip.id)?.activities.first { $0.title == "Ella spice garden" })
        #expect(garden.latitude == 6.8693)
        #expect(garden.longitude == 81.0441)
        #expect(map.unpinned.isEmpty)
        #expect(map.locateMessage == "Found all 1 on the map.")
    }

    @Test func placesThatCantBeFoundAreReported() async {
        let map = TripMapViewModel(tripID: trip.id, store: makeStore(), clock: FixedClock(now: now), places: FakePlaceSearch())
        map.selectedDay = 3
        await map.locateMissing()
        #expect(map.unpinned.count == 1)
        #expect(map.locateMessage == "Found 0 of 1. Edit the others to pick their place.")
    }

    @Test func theCameraFitsThePins() throws {
        let one = try #require(TripMapViewModel.region(fitting: [CLLocationCoordinate2D(latitude: 6.87, longitude: 81.06)]))
        #expect(one.span.latitudeDelta == 0.01, "a single pin isn't zoomed in to the street")

        let two = try #require(TripMapViewModel.region(fitting: [
            CLLocationCoordinate2D(latitude: 6.0, longitude: 80.0),
            CLLocationCoordinate2D(latitude: 7.0, longitude: 81.0),
        ]))
        #expect(two.center.latitude == 6.5)
        #expect(two.center.longitude == 80.5)
        #expect(two.span.latitudeDelta == 1.5)
        #expect(TripMapViewModel.region(fitting: []) == nil)
    }

    @Test func distancesAreReadable() {
        #expect(CLLocationDistance(347).distanceText == "350 m")
        #expect(CLLocationDistance(1240).distanceText == "1.2 km")
        #expect(CLLocationDistance(152_300).distanceText == "152 km")
    }

    @Test func pickingASearchResultPinsTheActivity() async throws {
        let store = makeStore()
        let search = FakePlaceSearch()
        search.results["Ravana"] = [MapPlace(name: "Ravana Falls", address: "Ella", latitude: 6.8406, longitude: 81.0536)]
        let form = ActivityFormViewModel(tripID: trip.id, day: 3, store: store, clock: FixedClock(now: now), places: search)
        form.title = "Waterfall stop"
        form.place = "Ravana"

        await form.searchPlaces()
        let result = try #require(form.placeResults.first)
        form.pin(result)
        #expect(form.place == "Ravana Falls")
        #expect(form.save())

        let saved = try #require(store.trip(trip.id)?.activities.first { $0.title == "Waterfall stop" })
        #expect(saved.latitude == 6.8406)
        #expect(saved.place == "Ravana Falls")
    }

    @Test func typingANewPlaceRemovesTheOldPin() throws {
        let store = makeStore()
        let bridge = activity("Nine Arch Bridge viewpoint")
        let form = ActivityFormViewModel(tripID: trip.id, day: 2, activityID: bridge.id, store: store,
                                         clock: FixedClock(now: now), places: FakePlaceSearch())
        #expect(form.pinnedPlace != nil)

        form.place = "Demodara"
        #expect(form.pinnedPlace == nil)
        #expect(form.save())
        #expect(store.trip(trip.id)?.activities.first { $0.id == bridge.id }?.hasCoordinates == false)
    }

    @Test func aMemoryFromAnArrivalIsLinkedToTheActivity() {
        let store = makeStore()
        let bridge = activity("Nine Arch Bridge viewpoint")
        let form = MemoryFormViewModel(tripID: trip.id, activityID: bridge.id, store: store, clock: FixedClock(now: now))
        #expect(form.linkedActivityID == bridge.id)
        #expect(form.place == "Nine Arch Bridge")

        let peak = activity("Little Adam's Peak")
        let later = MemoryFormViewModel(tripID: trip.id, activityID: peak.id, store: store, clock: FixedClock(now: now))
        #expect(later.day == 3, "the date moves to the activity's day")
        #expect(later.linkedActivityID == peak.id)
    }

    @Test func theNIBMTripIsWatchedAndAlertsAtNIBM() async throws {
        let store = makeStore()
        let id = try #require(store.addNIBMTrip())
        #expect(store.addNIBMTrip() == id, "adding it twice on the same day gives the same trip")
        let nibm = try #require(store.trip(id))
        #expect(nibm.dayNumber(at: now) == 1)
        #expect(nibm.cover == .nibmColombo)

        let (service, _, _, scheduler, _) = makeGeofences()
        await service.update(trips: [nibm])
        #expect(service.fences.count == 4)

        // Standing at the NIBM gate on Vidya Mawatha
        await service.checkArrival(at: CLLocation(latitude: 6.90639, longitude: 79.87083))
        #expect(scheduler.delivered.map(\.title) == ["You're at NIBM Colombo 7"])
    }

    @Test func coordinatesAreSavedInCoreData() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        try CoreDataTripRepository(context: context).save(trip)

        let loaded = try #require(try CoreDataTripRepository(context: context).loadTrips().first)
        let bridge = try #require(loaded.activities.first { $0.title == "Nine Arch Bridge viewpoint" })
        #expect(bridge.latitude == 6.8768)
        #expect(bridge.longitude == 81.0608)
        #expect(loaded.activities.first { $0.title == "Ella spice garden" }?.hasCoordinates == false)
    }

    @Test func coordinatesAreSynced() throws {
        let items = TripRecords.items(for: trip, accountID: "me")
        let bridge = activity("Nine Arch Bridge viewpoint")
        let record = try #require(items[ItemKey(collection: .activities, id: bridge.id.uuidString)]?.activity)
        #expect(record.latitude == 6.8768)
        #expect(record.longitude == 81.0608)

        // Activities uploaded before this version have no location and still load
        let old = #"{"position":0,"day":1,"title":"Walk","minutes":540,"place":"Galle","effort":"Low","isOutdoor":true,"isDone":false}"#
        let decoded = try JSONDecoder().decode(ActivityRecord.self, from: Data(old.utf8))
        #expect(decoded.latitude == nil)
        #expect(decoded.title == "Walk")
    }
}
