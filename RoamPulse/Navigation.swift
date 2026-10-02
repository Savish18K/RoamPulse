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
    case addActivity(tripID: UUID, day: Int)
    case addExpense(tripID: UUID)
    case recordMemory
    case addPhoto(memoryID: UUID?)
    case memory(UUID)
    case typeNote(UUID)
    case about

    var id: String {
        switch self {
        case .createTrip: "createTrip"
        case .addActivity(let tripID, let day): "addActivity-\(tripID)-\(day)"
        case .addExpense(let tripID): "addExpense-\(tripID)"
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

extension View {
    /// Registers every pushed screen. Added once at the root of each tab's NavigationStack.
    func appDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .tripDetail(let id, let day): TripDetailView(tripID: id, initialDay: day)
            case .packing(let id): PackingView(tripID: id)
            case .expenses(let id): ExpensesView(tripID: id)
            case .analytics(let id): ExpenseAnalyticsView(tripID: id)
            case .weather(let id): WeatherView(tripID: id)
            case .offlineMap(let id, let activityID): OfflineMapView(tripID: id, activityID: activityID)
            case .landmark(let id): LandmarkDetailView(landmarkID: id)
            case .statistics: StatisticsView()
            case .settings: SettingsView()
            }
        }
    }
}
