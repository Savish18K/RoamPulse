import SwiftUI

// MARK: - RoamPulseApp

@main
struct RoamPulseApp: App {
    /// Built once: Firebase, sign-in, sync, the real clock and the weather service.
    /// `live()` configures Firebase first, so it is ready before anything uses it.
    @State private var dependencies = AppDependencies.live()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .environment(dependencies.store)
                .environment(dependencies.session)
                .environment(router)
        }
    }
}

// MARK: - RootView

/// Decides between onboarding, signing in and the main app, shows the lock screen
/// and presents every sheet in the app.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(TripStore.self) private var store
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("appTheme") private var appTheme: AppTheme = .dark

    var body: some View {
        @Bindable var router = router

        Group {
            if !hasOnboarded {
                OnboardingView {
                    withAnimation { hasOnboarded = true }
                }
            } else {
                switch session.state {
                case .starting:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background)
                case .signedOut:
                    AuthView(viewModel: AuthViewModel(session: session))
                        .transition(.opacity)
                case .signedIn(let user):
                    MainTabView()
                        // A new account gets fresh screens, not the last person's scroll positions.
                        .id(user.uid)
                        .blur(radius: router.isLocked ? 20 : 0)
                        .allowsHitTesting(!router.isLocked)
                        .overlay {
                            if router.isLocked {
                                LockView().transition(.opacity)
                            }
                        }
                }
            }
        }
        .animation(.default, value: session.state)
        .onChange(of: session.user?.uid) {
            router.reset()
        }
        .sheet(item: $router.activeSheet) { sheet in
            SheetContent(sheet: sheet)
                // A sheet shows its own save errors; the alert below handles everything else.
                .errorAlert(store)
        }
        .errorAlert(store, isEnabled: router.activeSheet == nil)
        .preferredColorScheme(appTheme.colorScheme)
        .onAppear { router.isLocked = appLockEnabled }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && appLockEnabled && session.user != nil {
                router.isLocked = true
            }
        }
    }
}

// MARK: - MainTabView

/// The five tabs from the prototype. Each tab has its own NavigationStack.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            NavigationStack {
                HomeView(viewModel: HomeViewModel(store: dependencies.store, clock: dependencies.clock,
                                                  weather: dependencies.weather))
                    .appDestinations()
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(AppTab.home)

            NavigationStack {
                TripsListView(viewModel: TripsListViewModel(store: dependencies.store, clock: dependencies.clock,
                                                            weather: dependencies.weather))
                    .appDestinations()
            }
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
    let dependencies = AppDependencies.preview()
    MainTabView()
        .environment(dependencies)
        .environment(dependencies.store)
        .environment(dependencies.session)
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
