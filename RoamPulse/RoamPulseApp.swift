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
                .environment(dependencies.reminders)
                .environment(dependencies.appLock)
                .environment(router)
                .onAppear {
                    // Tapping a reminder opens its trip.
                    dependencies.notificationDelegate.openTrip = { [router] tripID in
                        router.openTrip(tripID)
                    }
                }
        }
    }
}

// MARK: - RootView

/// Decides between onboarding, signing in and the main app, shows the lock screen,
/// keeps reminders up to date and presents every sheet in the app.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(TripStore.self) private var store
    @Environment(AppSession.self) private var session
    @Environment(ReminderService.self) private var reminders
    @Environment(AppLock.self) private var appLock
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("appTheme") private var appTheme: AppTheme = .dark

    /// Everything the scheduled reminders depend on. When any of it changes, they are rescheduled.
    private struct ReminderInputs: Equatable {
        var trips: [Trip]
        var settings: ReminderSettings
        var isSignedIn: Bool
    }

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
                        .blur(radius: appLock.isLocked ? 20 : 0)
                        .allowsHitTesting(!appLock.isLocked)
                        .overlay {
                            if appLock.isLocked {
                                LockView().transition(.opacity)
                            }
                        }
                }
            }
        }
        // Hides trips and expenses in the app switcher when App Lock is on.
        .overlay {
            if appLock.isEnabled && session.user != nil && scenePhase != .active && !appLock.isLocked {
                PrivacyCover()
            }
        }
        .animation(.default, value: session.state)
        .animation(.default, value: appLock.isLocked)
        // Lock when the app opens with someone already signed in, but not right after signing in
        // with a password.
        .onAppear {
            if session.user != nil { appLock.lockOnLaunch() }
        }
        .onChange(of: session.state) { old, new in
            if old == .starting, case .signedIn = new { appLock.lockOnLaunch() }
        }
        .onChange(of: session.user?.uid) { _, uid in
            router.reset()
            if uid == nil {
                appLock.reset()
                Task { await reminders.removeAll() }
            }
        }
        .task(id: ReminderInputs(trips: store.trips, settings: reminders.settings, isSignedIn: session.user != nil)) {
            guard session.user != nil else { return }
            // Wait for a burst of edits (e.g. dragging activities) to finish before rescheduling.
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            await reminders.reschedule(trips: store.trips)
        }
        .sheet(item: $router.activeSheet) { sheet in
            SheetContent(sheet: sheet)
                // A sheet shows its own save errors; the alert below handles everything else.
                .errorAlert(store)
        }
        .errorAlert(store, isEnabled: router.activeSheet == nil)
        .preferredColorScheme(appTheme.colorScheme)
        .onChange(of: scenePhase) { _, phase in
            guard session.user != nil else { return }
            switch phase {
            case .background: appLock.didEnterBackground()
            case .active: appLock.didBecomeActive()
            default: break
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

            NavigationStack(path: $router.tripsPath) {
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
        .previewEnvironment(dependencies)
        .preferredColorScheme(.dark)
}
