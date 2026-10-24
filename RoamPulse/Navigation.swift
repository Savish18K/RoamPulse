import SwiftUI
import Observation

enum AppTab: Hashable {
    case home, trips, journal, insights, profile
}

enum AppRoute: Hashable {
    case tripDetail(UUID, day: Int? = nil)
    case packing(UUID)
    case expenses(UUID)
    case analytics(UUID)
    case weather(UUID)
    case offlineMap(UUID, activityID: UUID? = nil)
    case landmark(UUID)
    case statistics
    case settings
}

enum AppSheet: Identifiable {
    case createTrip
    case editTrip(UUID)
    case addActivity(tripID: UUID, day: Int)
    case editActivity(tripID: UUID, activityID: UUID)
    case addExpense(tripID: UUID)
    case editExpense(tripID: UUID, expenseID: UUID)
    case newMemory(tripID: UUID?, start: MemoryFormStart)
    case editMemory(UUID)
    case memory(UUID)
    case typeNote(UUID)
    case about
    case shareTrip(UUID)
    case joinTrip
    case editProfile
    case deleteAccount

    var id: String {
        switch self {
        case .createTrip: "createTrip"
        case .editTrip(let id): "editTrip-\(id)"
        case .addActivity(let tripID, let day): "addActivity-\(tripID)-\(day)"
        case .editActivity(_, let activityID): "editActivity-\(activityID)"
        case .addExpense(let tripID): "addExpense-\(tripID)"
        case .editExpense(_, let expenseID): "editExpense-\(expenseID)"
        case .newMemory(let tripID, let start): "newMemory-\(tripID?.uuidString ?? "current")-\(start)"
        case .editMemory(let id): "editMemory-\(id)"
        case .memory(let id): "memory-\(id)"
        case .typeNote(let id): "typeNote-\(id)"
        case .about: "about"
        case .shareTrip(let id): "shareTrip-\(id)"
        case .joinTrip: "joinTrip"
        case .editProfile: "editProfile"
        case .deleteAccount: "deleteAccount"
        }
    }
}

enum MemoryFormStart: Hashable {
    case writing, recording, photos
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var activeSheet: AppSheet?
    // Kept here so a notification can open a trip
    var tripsPath: [AppRoute] = []
    // Opens Insights with this search
    var insightsSearch: String?

    func reset() {
        selectedTab = .home
        activeSheet = nil
        tripsPath = []
    }

    func searchInsights(for text: String) {
        activeSheet = nil
        insightsSearch = text
        selectedTab = .insights
    }

    func openTrip(_ id: UUID) {
        activeSheet = nil
        selectedTab = .trips
        tripsPath = [.tripDetail(id)]
    }
}

// All pushed screens and sheets are created here

extension View {
    func appDestinations() -> some View {
        modifier(AppDestinations())
    }
}

private struct AppDestinations: ViewModifier {
    @Environment(AppDependencies.self) private var dependencies

    func body(content: Content) -> some View {
        content.navigationDestination(for: AppRoute.self) { route in
            destination(for: route)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        let store = dependencies.store
        let clock = dependencies.clock
        let weather = dependencies.weather

        switch route {
        case .tripDetail(let id, let day):
            TripDetailView(viewModel: TripDetailViewModel(tripID: id, initialDay: day, store: store, clock: clock, weather: weather))
        case .packing(let id):
            PackingView(viewModel: PackingViewModel(tripID: id, store: store, weather: weather))
        case .expenses(let id):
            ExpensesView(viewModel: ExpensesViewModel(tripID: id, store: store))
        case .analytics(let id):
            ExpenseAnalyticsView(viewModel: ExpenseAnalyticsViewModel(tripID: id, store: store, clock: clock))
        case .weather(let id):
            WeatherView(viewModel: WeatherViewModel(tripID: id, store: store, weather: weather))
        case .offlineMap(let id, let activityID):
            OfflineMapView(tripID: id, activityID: activityID)
        case .landmark(let id):
            LandmarkDetailView(landmarkID: id)
        case .statistics:
            StatisticsView()
        case .settings:
            SettingsView()
        }
    }
}

struct SheetContent: View {
    let sheet: AppSheet
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let store = dependencies.store
        let clock = dependencies.clock

        switch sheet {
        case .createTrip:
            TripFormView(viewModel: TripFormViewModel(store: store, clock: clock, weather: dependencies.weather))
        case .editTrip(let id):
            TripFormView(viewModel: TripFormViewModel(tripID: id, store: store, clock: clock, weather: dependencies.weather))
        case .addActivity(let tripID, let day):
            ActivityFormView(viewModel: ActivityFormViewModel(tripID: tripID, day: day, store: store, clock: clock))
        case .editActivity(let tripID, let activityID):
            ActivityFormView(viewModel: ActivityFormViewModel(tripID: tripID, day: 1, activityID: activityID, store: store, clock: clock))
        case .addExpense(let tripID):
            ExpenseFormView(viewModel: ExpenseFormViewModel(tripID: tripID, store: store, clock: clock))
        case .editExpense(let tripID, let expenseID):
            ExpenseFormView(viewModel: ExpenseFormViewModel(tripID: tripID, expenseID: expenseID, store: store, clock: clock))
        case .newMemory(let tripID, let start):
            MemoryFormView(viewModel: MemoryFormViewModel(tripID: tripID, store: store, clock: clock,
                                                          recorder: dependencies.recorder, voice: dependencies.voice),
                           start: start)
        case .editMemory(let id):
            MemoryFormView(viewModel: MemoryFormViewModel(memoryID: id, store: store, clock: clock,
                                                          recorder: dependencies.recorder, voice: dependencies.voice))
        case .memory(let id):
            MemoryDetailView(memoryID: id)
        case .typeNote(let id):
            TypeNoteView(memoryID: id)
        case .about:
            AboutView()
        case .shareTrip(let id):
            ShareTripView(viewModel: ShareTripViewModel(tripID: id, store: store, sync: dependencies.sync))
        case .joinTrip:
            JoinTripView(viewModel: JoinTripViewModel(store: store, sync: dependencies.sync))
        case .editProfile:
            EditProfileView()
        case .deleteAccount:
            DeleteAccountView()
        }
    }
}
