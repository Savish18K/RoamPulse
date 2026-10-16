import Foundation
import Observation

/// Creates the app's services once and hands them out (dependency injection).
///
/// Views read this from the environment and pass what each view model needs into the view
/// model's initialiser, so a view model never creates its own services. Tests and previews
/// build the same view models with stand-ins: an in-memory repository and a fixed clock.
@MainActor
@Observable
final class AppDependencies {
    let clock: Clock
    let weather: WeatherService
    let store: TripStore

    init(repository: TripRepository, clock: Clock, weather: WeatherService) {
        self.clock = clock
        self.weather = weather
        self.store = TripStore(repository: repository, clock: clock)
    }

    /// The real app: Core Data on disk and the real time.
    static func live() -> AppDependencies {
        let persistence = PersistenceController.shared
        let clock = SystemClock()
        let dependencies = AppDependencies(
            repository: CoreDataTripRepository(context: persistence.container.viewContext),
            clock: clock,
            weather: MockWeatherService(clock: clock)
        )
        if let error = persistence.loadError {
            dependencies.store.errorMessage = "Couldn't open the database. \(error.localizedDescription)"
        } else {
            dependencies.store.seedSampleDataIfNeeded()
        }
        return dependencies
    }

    /// SwiftUI previews: the sample trips in memory, nothing saved.
    static func preview() -> AppDependencies {
        let clock = SystemClock()
        let sample = SampleData.make(now: clock.now)
        return AppDependencies(
            repository: InMemoryTripRepository(trips: sample.trips, memories: sample.memories),
            clock: clock,
            weather: MockWeatherService(clock: clock)
        )
    }

    /// The active sample trip, for previews.
    var previewTripID: UUID { store.activeTrip?.id ?? store.trips.first?.id ?? UUID() }
}
