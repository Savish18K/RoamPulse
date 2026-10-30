import SwiftUI
import Observation

enum AppTab: Hashable, CaseIterable {
    case home, trips, journal, insights, profile

    var title: String {
        switch self {
        case .home: "Home"
        case .trips: "Trips"
        case .journal: "Journal"
        case .insights: "Insights"
        case .profile: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .trips: "safari"
        case .journal: "book"
        case .insights: "chart.xyaxis.line"
        case .profile: "person"
        }
    }
}

// What's selected in the iPad sidebar: one of the app's sections, or a trip
enum SidebarItem: Hashable {
    case section(AppTab)
    case trip(UUID)
}

enum AppRoute: Hashable {
    case tripDetail(UUID, day: Int? = nil)
    case packing(UUID)
    case expenses(UUID)
    case analytics(UUID)
    // fromTrip: opened from that trip's screen, so "View Day" goes back instead of opening it again
    case weather(UUID, fromTrip: Bool = false)
    case map(UUID, activityID: UUID? = nil)
    case landmark(String)
    // The journal of one trip, opened from inside that trip
    case journal(UUID)
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
    case newMemory(tripID: UUID?, start: MemoryFormStart, activityID: UUID? = nil)
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
        case .newMemory(let tripID, let start, let activityID):
            "newMemory-\(tripID?.uuidString ?? "current")-\(start)-\(activityID?.uuidString ?? "")"
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
    // iPhone tab bar. Changing it also moves the iPad sidebar, so "Open Journal" works on both
    var selectedTab: AppTab = .home {
        didSet {
            if sidebarSelection != .section(selectedTab) {
                sidebarSelection = .section(selectedTab)
            }
        }
    }
    // iPad sidebar. Picking a section there keeps the tab in step for when the window gets narrow
    var sidebarSelection: SidebarItem? = .section(.home) {
        didSet {
            if case .section(let tab) = sidebarSelection, tab != selectedTab {
                selectedTab = tab
            }
            detailPath = []
        }
    }
    // Screens pushed in the iPad detail column
    var detailPath: [AppRoute] = []
    var activeSheet: AppSheet?
    // Kept here so a notification can open a trip
    var tripsPath: [AppRoute] = []
    // Opens Insights with this search
    var insightsSearch: String?
    // Asks the trip screen underneath to show a day, e.g. from the weather screen
    var dayRequest: DayRequest?

    struct DayRequest: Equatable {
        let tripID: UUID
        let day: Int
    }

    func reset() {
        selectedTab = .home
        activeSheet = nil
        tripsPath = []
        detailPath = []
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
        // On iPad the trip opens straight from the sidebar
        sidebarSelection = .trip(id)
    }

    // Taps on the Home Screen widget
    func open(_ link: WidgetLink) {
        switch link {
        case .trip(let id): openTrip(id)
        case .recordMemory(let id): activeSheet = .newMemory(tripID: id, start: .recording)
        }
    }

    func recordMemory(tripID: UUID, activityID: UUID) {
        activeSheet = .newMemory(tripID: tripID, start: .writing, activityID: activityID)
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
        case .weather(let id, let fromTrip):
            WeatherView(viewModel: WeatherViewModel(tripID: id, store: store, weather: weather), fromTrip: fromTrip)
        case .map(let id, let activityID):
            TripMapView(viewModel: TripMapViewModel(tripID: id, activityID: activityID, store: store, clock: clock,
                                                    places: dependencies.places))
        case .landmark(let id):
            LandmarkDetailView(landmarkID: id)
        case .journal(let id):
            JournalView(viewModel: JournalViewModel(store: store, tripID: id))
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
            ActivityFormView(viewModel: ActivityFormViewModel(tripID: tripID, day: day, store: store, clock: clock,
                                                              places: dependencies.places))
        case .editActivity(let tripID, let activityID):
            ActivityFormView(viewModel: ActivityFormViewModel(tripID: tripID, day: 1, activityID: activityID, store: store,
                                                              clock: clock, places: dependencies.places))
        case .addExpense(let tripID):
            ExpenseFormView(viewModel: ExpenseFormViewModel(tripID: tripID, store: store, clock: clock))
        case .editExpense(let tripID, let expenseID):
            ExpenseFormView(viewModel: ExpenseFormViewModel(tripID: tripID, expenseID: expenseID, store: store, clock: clock))
        case .newMemory(let tripID, let start, let activityID):
            MemoryFormView(viewModel: MemoryFormViewModel(tripID: tripID, activityID: activityID, store: store, clock: clock,
                                                          recorder: dependencies.recorder, voice: dependencies.voice,
                                                          recognizer: dependencies.landmarkRecognizer),
                           start: start)
        case .editMemory(let id):
            MemoryFormView(viewModel: MemoryFormViewModel(memoryID: id, store: store, clock: clock,
                                                          recorder: dependencies.recorder, voice: dependencies.voice,
                                                          recognizer: dependencies.landmarkRecognizer))
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
