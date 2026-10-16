import SwiftUI
import Observation

enum AppTab: Hashable {
    case home, trips, journal, insights, profile
}

/// Screens that are pushed onto a tab's NavigationStack.
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

/// Screens that are presented as sheets from anywhere in the app.
enum AppSheet: Identifiable {
    case createTrip
    case editTrip(UUID)
    case addActivity(tripID: UUID, day: Int)
    case editActivity(tripID: UUID, activityID: UUID)
    case addExpense(tripID: UUID)
    case editExpense(tripID: UUID, expenseID: UUID)
    case recordMemory
    case addPhoto(memoryID: UUID?)
    case memory(UUID)
    case typeNote(UUID)
    case about

    var id: String {
        switch self {
        case .createTrip: "createTrip"
        case .editTrip(let id): "editTrip-\(id)"
        case .addActivity(let tripID, let day): "addActivity-\(tripID)-\(day)"
        case .editActivity(_, let activityID): "editActivity-\(activityID)"
        case .addExpense(let tripID): "addExpense-\(tripID)"
        case .editExpense(_, let expenseID): "editExpense-\(expenseID)"
        case .recordMemory: "recordMemory"
        case .addPhoto(let memoryID): "addPhoto-\(memoryID?.uuidString ?? "new")"
        case .memory(let id): "memory-\(id)"
        case .typeNote(let id): "typeNote-\(id)"
        case .about: "about"
        }
    }
}

/// App-wide navigation state: selected tab, current sheet and app lock.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var activeSheet: AppSheet?
    var isLocked = false
}

// MARK: - Building screens

// `AppDestinations` and `SheetContent` are the only places pushed screens and sheets are created.
// Each screen gets a view model built with the shared services from `AppDependencies`.

extension View {
    /// Registers every pushed screen. Added once at the root of each tab's NavigationStack.
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

/// Builds the screen for a sheet. Used by RootView's `.sheet(item:)`.
struct SheetContent: View {
    let sheet: AppSheet
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let store = dependencies.store
        let clock = dependencies.clock

        switch sheet {
        case .createTrip:
            TripFormView(viewModel: TripFormViewModel(store: store, clock: clock))
        case .editTrip(let id):
            TripFormView(viewModel: TripFormViewModel(tripID: id, store: store, clock: clock))
        case .addActivity(let tripID, let day):
            ActivityFormView(viewModel: ActivityFormViewModel(tripID: tripID, day: day, store: store, clock: clock))
        case .editActivity(let tripID, let activityID):
            ActivityFormView(viewModel: ActivityFormViewModel(tripID: tripID, day: 1, activityID: activityID, store: store, clock: clock))
        case .addExpense(let tripID):
            ExpenseFormView(viewModel: ExpenseFormViewModel(tripID: tripID, store: store, clock: clock))
        case .editExpense(let tripID, let expenseID):
            ExpenseFormView(viewModel: ExpenseFormViewModel(tripID: tripID, expenseID: expenseID, store: store, clock: clock))
        case .recordMemory:
            RecordMemoryView()
        case .addPhoto(let memoryID):
            PhotoPickerView(memoryID: memoryID)
        case .memory(let id):
            MemoryDetailView(memoryID: id)
        case .typeNote(let id):
            TypeNoteView(memoryID: id)
        case .about:
            AboutView()
        }
    }
}
