import SwiftUI

// MARK: - RoamPulseApp

@main
struct RoamPulseApp: App {
    @State private var store = TripStore()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
        }
    }
}

// MARK: - RootView

/// Decides between onboarding and the main app, shows the lock screen
/// and presents every sheet in the app.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("appTheme") private var appTheme: AppTheme = .dark

    var body: some View {
        @Bindable var router = router

        Group {
            if hasOnboarded {
                MainTabView()
                    .blur(radius: router.isLocked ? 20 : 0)
                    .allowsHitTesting(!router.isLocked)
                    .overlay {
                        if router.isLocked {
                            LockView().transition(.opacity)
                        }
                    }
            } else {
                OnboardingView {
                    withAnimation { hasOnboarded = true }
                }
            }
        }
        .sheet(item: $router.activeSheet) { sheet in
            sheetContent(sheet)
        }
        .preferredColorScheme(appTheme.colorScheme)
        .onAppear { router.isLocked = appLockEnabled }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && appLockEnabled {
                router.isLocked = true
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .createTrip: CreateTripView()
        case .addActivity(let tripID, let day): AddActivityView(tripID: tripID, day: day)
        case .addExpense(let tripID): AddExpenseView(tripID: tripID)
        case .recordMemory: RecordMemoryView()
        case .addPhoto(let memoryID): PhotoPickerView(memoryID: memoryID)
        case .memory(let id): MemoryDetailView(memoryID: id)
        case .typeNote(let id): TypeNoteView(memoryID: id)
        case .about: AboutView()
        }
    }
}

// MARK: - MainTabView

/// The five tabs from the prototype. Each tab has its own NavigationStack.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            NavigationStack { HomeView().appDestinations() }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)

            NavigationStack { TripsListView().appDestinations() }
                .tabItem { Label("Trips", systemImage: "safari") }
                .tag(AppTab.trips)

            NavigationStack { JournalView().appDestinations() }
                .tabItem { Label("Journal", systemImage: "book") }
                .tag(AppTab.journal)

            NavigationStack { InsightsView().appDestinations() }
                .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.insights)

            NavigationStack { ProfileView().appDestinations() }
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(AppTab.profile)
        }
    }
}

#Preview {
    MainTabView()
        .environment(TripStore())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
