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
    /// "Add Photos" opens the form with the photo picker showing.
    case newMemory(tripID: UUID?, withPhotos: Bool)
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
        case .newMemory(let tripID, let withPhotos): "newMemory-\(tripID?.uuidString ?? "current")-\(withPhotos)"
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

/// App-wide navigation state: selected tab, current sheet, and the Trips tab's pushed screens.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var activeSheet: AppSheet?
    /// Screens pushed on the Trips tab, so a notification can open a trip.
    var tripsPath: [AppRoute] = []
    /// Set to open Insights searching for this text (e.g. a place or person tapped on a memory).
    var insightsSearch: String?

    /// Back to the Home tab with no sheet open, e.g. after signing out.
    func reset() {
        selectedTab = .home
        activeSheet = nil
        tripsPath = []
    }

    /// Opens Insights → Search for every memory mentioning `text`.
    func searchInsights(for text: String) {
        activeSheet = nil
        insightsSearch = text
        selectedTab = .insights
    }

    /// Shows a trip's detail screen, e.g. after tapping one of its reminders.
    func openTrip(_ id: UUID) {
        activeSheet = nil
        selectedTab = .trips
        tripsPath = [.tripDetail(id)]
    }
}

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
        case .newMemory(let tripID, let withPhotos):
            MemoryFormView(viewModel: MemoryFormViewModel(tripID: tripID, store: store, clock: clock),
                           opensPhotoPicker: withPhotos)
        case .editMemory(let id):
            MemoryFormView(viewModel: MemoryFormViewModel(memoryID: id, store: store, clock: clock))
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
