import Foundation
import Testing
@testable import RoamPulse

/// OpenWeatherMap: reading its JSON, building the forecast screens, the advice for each activity,
/// and the service's caching, offline and error behaviour, all with saved responses (no network).
@MainActor
struct WeatherTests {
    /// Sunday 13 December 2026, 16:40, like the prototype.
    let now = Calendar.trip.date(2026, 12, 13, 16, 40)
    let calendar = Calendar.trip

    /// Real-shaped responses (trimmed to the fields the app reads).
    static let currentJSON = """
    {"weather":[{"id":500,"main":"Rain","description":"light rain","icon":"10d"}],
     "main":{"temp":19.4,"feels_like":19.6,"temp_min":18.2,"temp_max":21.7,"pressure":1012,"humidity":88},
     "wind":{"speed":3.1,"deg":240},"sys":{"country":"LK","sunrise":1765586400,"sunset":1765627320},
     "name":"Ella","dt":1765624800,"timezone":19800}
    """

    static let forecastJSON = """
    {"cod":"200","cnt":2,"list":[
      {"dt":1765627200,"main":{"temp":19.0,"humidity":90},"weather":[{"id":501,"main":"Rain","description":"moderate rain","icon":"10n"}],"pop":0.82,"rain":{"3h":4.2}},
      {"dt":1765638000,"main":{"temp":17.0,"humidity":92},"weather":[{"id":804,"main":"Clouds","description":"overcast clouds","icon":"04n"}],"pop":0.2}
    ],"city":{"name":"Ella","country":"LK","timezone":19800}}
    """

    static let placesJSON = """
    [{"name":"Ella","lat":37.9,"lon":22.1,"country":"GR"},
     {"name":"Ella","lat":6.8667,"lon":81.0466,"country":"LK","state":"Uva Province"}]
    """

    private func trip(activities: [Activity] = [], coordinates: Bool = true) -> Trip {
        var trip = Trip(name: "Hill Country Explorer", destination: "Kandy to Ella",
                        startDate: calendar.date(2026, 12, 12), endDate: calendar.date(2026, 12, 15),
                        budget: 0, members: [], cover: .hillTrain)
        trip.activities = activities
        if coordinates {
            trip.latitude = 6.8667
            trip.longitude = 81.0466
        }
        return trip
    }

    /// One 3-hour step of a forecast.
    private func slot(_ day: Int, _ hour: Int, rain: Int, temperature: Int = 20, code: Int = 500, mm: Double = 0) -> ForecastSlot {
        ForecastSlot(start: calendar.date(2026, 12, day, hour), temperature: temperature, rainChance: rain, rainMM: mm,
                     conditionCode: code, condition: "Rain", symbol: ForecastBuilder.symbol(code: code, icon: "10d"))
    }

    private func snapshot(_ slots: [ForecastSlot]) -> WeatherSnapshot {
        WeatherSnapshot(location: "Ella", condition: "Rain", symbol: "cloud.rain.fill", temperature: 19, high: 22, low: 15,
                        humidity: 88, windKmh: 11, rainChance: 70, sunset: "18:02", fetchedAt: now, hourly: [],
                        daily: [], slots: slots)
    }

    @Test func realResponsesAreRead() throws {
        let current = try OpenWeatherMapClient.decoder.decode(OWMCurrent.self, from: Data(Self.currentJSON.utf8))
        #expect(current.main.tempMax == 21.7, "snake_case temp_max becomes tempMax")
        #expect(current.weather.first?.description == "light rain")

        let forecast = try OpenWeatherMapClient.decoder.decode(OWMForecast.self, from: Data(Self.forecastJSON.utf8))
        #expect(forecast.list.count == 2)
        #expect(forecast.list[0].rain?.threeHours == 4.2, "the \"3h\" key")
        #expect(forecast.list[0].pop == 0.82)
        #expect(forecast.list[1].rain == nil)
    }

    @Test func theCachedCopyReadsBackTheSame() throws {
        let bundle = OpenWeatherMapBundle(
            placeName: "Ella",
            current: try OpenWeatherMapClient.decoder.decode(OWMCurrent.self, from: Data(Self.currentJSON.utf8)),
            forecast: try OpenWeatherMapClient.decoder.decode(OWMForecast.self, from: Data(Self.forecastJSON.utf8)))
        let saved = try OpenWeatherMapClient.encoder.encode(bundle)
        #expect(try OpenWeatherMapClient.decoder.decode(OpenWeatherMapBundle.self, from: saved) == bundle)
    }

    @Test func theSnapshotUsesTheCurrentWeatherAndTheFutureSteps() throws {
        let bundle = OpenWeatherMapBundle(
            placeName: "Ella",
            current: try OpenWeatherMapClient.decoder.decode(OWMCurrent.self, from: Data(Self.currentJSON.utf8)),
            forecast: try OpenWeatherMapClient.decoder.decode(OWMForecast.self, from: Data(Self.forecastJSON.utf8)))
        let fetched = Date(timeIntervalSince1970: 1765624800)
        let weather = ForecastBuilder.snapshot(from: bundle, for: trip(), now: fetched, fetchedAt: fetched, isOffline: false)

        #expect(weather.temperature == 19)
        #expect(weather.condition == "Light rain", "capitalised")
        #expect(weather.windKmh == 11, "3.1 m/s")
        #expect(weather.slots.count == 2)
        #expect(weather.slots[0].rainChance == 82)
        #expect(weather.slots[0].rainMM == 4.2)
        #expect(weather.hourly.first?.label == "Now")
        #expect(weather.hourly.count == 3)
        #expect(weather.source == .openWeatherMap)
    }

    @Test func stepsThatHaveEndedAreDroppedFromAnOldForecast() throws {
        let bundle = OpenWeatherMapBundle(
            placeName: "Ella",
            current: try OpenWeatherMapClient.decoder.decode(OWMCurrent.self, from: Data(Self.currentJSON.utf8)),
            forecast: try OpenWeatherMapClient.decoder.decode(OWMForecast.self, from: Data(Self.forecastJSON.utf8)))
        let fetched = Date(timeIntervalSince1970: 1765624800)
        let fiveHoursLater = fetched.addingTimeInterval(5 * 3600)
        let weather = ForecastBuilder.snapshot(from: bundle, for: trip(), now: fiveHoursLater, fetchedAt: fetched, isOffline: true)
        #expect(weather.slots.count == 1)
        #expect(weather.temperature == 17, "an old 'current' is replaced by the step for now")
        #expect(weather.isOffline)
    }

    @Test func eachDayShowsItsWettestWeatherWhenRainIsLikely() {
        let slots = [slot(14, 9, rain: 10, temperature: 18, code: 801), slot(14, 12, rain: 30, temperature: 22, code: 802),
                     slot(14, 15, rain: 90, temperature: 21, code: 502)]
        let days = ForecastBuilder.daily(from: slots, trip: trip())
        #expect(days.count == 1)
        #expect(days[0].tripDay == 3)
        #expect(days[0].rainChance == 90)
        #expect(days[0].high == 22 && days[0].low == 18)
        #expect(days[0].symbol == ForecastBuilder.symbol(code: 502, icon: "10d"))
    }

    @Test(arguments: [(211, "11d", "cloud.bolt.rain.fill"), (500, "10d", "cloud.rain.fill"), (502, "10d", "cloud.heavyrain.fill"),
                      (800, "01d", "sun.max.fill"), (800, "01n", "moon.stars.fill"), (741, "50d", "cloud.fog.fill"),
                      (804, "04d", "cloud.fill")])
    func conditionCodesBecomeSymbols(code: Int, icon: String, symbol: String) {
        #expect(ForecastBuilder.symbol(code: code, icon: icon) == symbol)
    }

    /// Day 3 (Mon 14 Dec): dry morning, heavy rain 12:00–18:00.
    private var rainyDay: WeatherSnapshot {
        snapshot([slot(14, 6, rain: 10, code: 801), slot(14, 9, rain: 20, code: 802), slot(14, 12, rain: 70, code: 500),
                  slot(14, 15, rain: 90, code: 502, mm: 6), slot(14, 18, rain: 30, code: 803)])
    }

    @Test func anOutdoorActivityInHeavyRainIsWarnedWithADrierTime() throws {
        let falls = Activity(day: 3, title: "Ravana Falls", minutes: 15 * 60, place: "Ella", effort: .moderate, isOutdoor: true)
        let advisory = try #require(WeatherAdvisor.advisory(for: falls, in: trip(activities: [falls]), snapshot: rainyDay))

        #expect(advisory.kind == .rain)
        #expect(advisory.title == "Heavy rain likely")
        #expect(advisory.window == "12:00–18:00", "the wet steps next to each other are one window")
        #expect(advisory.message.contains("Drier around 06:00 (10%)"))
    }

    @Test func indoorFinishedAndFarAwayActivitiesGetNoWarning() {
        let indoor = Activity(day: 3, title: "Spice garden", minutes: 15 * 60, place: "", effort: .low)
        var done = Activity(day: 3, title: "Falls", minutes: 15 * 60, place: "", effort: .low, isOutdoor: true)
        done.isDone = true
        let beyondForecast = Activity(day: 4, title: "Hike", minutes: 9 * 60, place: "", effort: .high, isOutdoor: true)
        let plan = trip(activities: [indoor, done, beyondForecast])

        #expect(WeatherAdvisor.advisory(for: indoor, in: plan, snapshot: rainyDay) == nil)
        #expect(WeatherAdvisor.advisory(for: done, in: plan, snapshot: rainyDay) == nil)
        #expect(WeatherAdvisor.advisory(for: beyondForecast, in: plan, snapshot: rainyDay) == nil, "forecast not available yet")
    }

    @Test func aHardActivityInTheHeatIsWarned() {
        let hike = Activity(day: 3, title: "Little Adam's Peak", minutes: 12 * 60, place: "", effort: .high, isOutdoor: true)
        let hot = snapshot([slot(14, 12, rain: 0, temperature: 33, code: 800)])
        #expect(WeatherAdvisor.advisory(for: hike, in: trip(activities: [hike]), snapshot: hot)?.kind == .heat)

        var easy = hike
        easy.effort = .low
        #expect(WeatherAdvisor.advisory(for: easy, in: trip(activities: [easy]), snapshot: hot) == nil)
    }

    @Test func theHeadlineIsTheNextActivityAtRisk() {
        let morning = Activity(day: 3, title: "Tea factory", minutes: 13 * 60, place: "", effort: .low, isOutdoor: true)
        let falls = Activity(day: 3, title: "Ravana Falls", minutes: 15 * 60, place: "", effort: .moderate, isOutdoor: true)
        let plan = trip(activities: [falls, morning])

        let headline = WeatherAdvisor.headline(for: plan, snapshot: rainyDay, now: now)
        #expect(headline?.day == 3)
        #expect(headline?.shortMessage.hasPrefix("Tea factory at 13:00") == true)
        #expect(WeatherAdvisor.advisoryDays(for: plan, in: rainyDay) == [3])

        let afterLunch = calendar.date(2026, 12, 14, 14)
        #expect(WeatherAdvisor.headline(for: plan, snapshot: rainyDay, now: afterLunch)?.shortMessage.hasPrefix("Ravana Falls") == true)
    }

    private func makeService(http: FakeHTTPClient, trip: Trip, clock: Clock? = nil)
        -> (OpenWeatherMapService, TripStore) {
        let clock = clock ?? FixedClock(now: now)
        let store = TripStore(repository: InMemoryTripRepository(trips: [trip]), clock: clock)
        let service = OpenWeatherMapService(client: OpenWeatherMapClient(apiKey: "test", http: http), clock: clock)
        service.store = store
        return (service, store)
    }

    private func onlineHTTP() -> FakeHTTPClient {
        let http = FakeHTTPClient()
        http.responses["/data/2.5/weather"] = (200, Data(Self.currentJSON.utf8))
        http.responses["/data/2.5/forecast"] = (200, Data(Self.forecastJSON.utf8))
        http.responses["/geo/1.0/direct"] = (200, Data(Self.placesJSON.utf8))
        return http
    }

    @Test func aForecastIsDownloadedOnceAndReusedFor15Minutes() async throws {
        let http = onlineHTTP()
        let clock = MutableClock(Date(timeIntervalSince1970: 1765624800))
        let ella = trip()
        let (service, store) = makeService(http: http, trip: ella, clock: clock)
        var alerts = 0
        service.onNewForecast = { _, _ in alerts += 1 }

        _ = try await service.forecast(for: ella)
        #expect(store.cachedForecast(for: ella.id) != nil, "saved for offline use")

        clock.advance(minutes: 10)
        _ = try await service.forecast(for: ella)
        #expect(http.count("/data/2.5/forecast") == 1, "reused, not downloaded again")

        _ = try await service.forecast(for: ella, refresh: true)
        #expect(http.count("/data/2.5/forecast") == 2, "pull to refresh always downloads")
        #expect(alerts == 2, "weather alerts are checked after every download")
    }

    @Test func offlineTheSavedForecastIsShown() async throws {
        let http = onlineHTTP()
        let ella = trip()
        // Keep the store: the service only holds it weakly (the app's AppDependencies owns it).
        let (service, store) = makeService(http: http, trip: ella)
        _ = try await service.forecast(for: ella)

        http.error = URLError(.notConnectedToInternet)
        let offline = try await service.forecast(for: ella, refresh: true)
        #expect(offline.isOffline)
        #expect(offline.location == "Ella")
        #expect(store.cachedForecast(for: ella.id) != nil)
    }

    @Test func offlineWithNothingSavedExplainsWhy() async {
        let http = FakeHTTPClient()
        http.error = URLError(.notConnectedToInternet)
        let (service, _) = makeService(http: http, trip: trip())
        await #expect(throws: WeatherError.offline) {
            _ = try await service.forecast(for: trip())
        }
    }

    @Test func aRejectedKeyIsExplained() async {
        let http = onlineHTTP()
        http.responses["/data/2.5/weather"] = (401, Data())
        let (service, _) = makeService(http: http, trip: trip())
        await #expect(throws: WeatherError.invalidAPIKey) {
            _ = try await service.forecast(for: trip())
        }
    }

    @Test func aTypedDestinationIsLookedUpOnceInSriLanka() async throws {
        let http = onlineHTTP()
        let typed = trip(coordinates: false)
        let (service, store) = makeService(http: http, trip: typed)

        _ = try await service.forecast(for: typed)
        let saved = try #require(store.trip(typed.id))
        #expect(saved.latitude == 6.8667, "Ella, LK rather than Ella, Greece")
        #expect(saved.longitude == 81.0466)

        _ = try await service.forecast(for: saved, refresh: true)
        #expect(http.count("/geo/1.0/direct") == 1, "the coordinates are saved on the trip")
    }

    @Test func screensAskingAtTheSameTimeShareOneDownload() async throws {
        let http = onlineHTTP()
        let ella = trip()
        let (service, _) = makeService(http: http, trip: ella)
        async let first = service.forecast(for: ella)
        async let second = service.forecast(for: ella)
        _ = try await (first, second)
        #expect(http.count("/data/2.5/forecast") == 1)
    }

    @Test func searchSuggestionsShowTheRegion() async throws {
        let (service, _) = makeService(http: onlineHTTP(), trip: trip())
        let places = try await service.searchPlaces("Ella")
        #expect(places.map(\.region) == ["GR", "Uva Province, LK"])
    }

    @Test func theFormSavesThePickedPlacesCoordinates() async throws {
        let store = TripStore(repository: InMemoryTripRepository(), clock: FixedClock(now: now))
        let form = TripFormViewModel(store: store, clock: FixedClock(now: now), weather: MockWeatherService(clock: FixedClock(now: now)))
        form.name = "Ella weekend"
        form.destination = "ell"
        await form.searchPlaces()
        let ella = try #require(form.placeSuggestions.first { $0.name == "Ella" })

        form.pick(ella)
        #expect(form.destination == "Ella")
        #expect(form.save())
        #expect(store.trips.first?.latitude == ella.latitude)

        form.destination = "Galle"
        #expect(form.pickedPlace == nil, "typing something else forgets the picked place")
    }
}
