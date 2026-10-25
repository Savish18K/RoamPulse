import SwiftUI

// iPad (and any wide window): a sidebar with the app's sections and every trip, and the
// selected screen next to it. Narrow windows (iPhone, iPad Slide Over) use MainTabView instead
struct MainSplitView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies
    @Environment(TripStore.self) private var store
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var router = router

        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            NavigationStack(path: $router.detailPath) {
                detail(for: router.sidebarSelection ?? .section(.home))
                    // Set before appDestinations, so screens pushed later still get their back button
                    .environment(\.isDetailRoot, true)
                    .appDestinations()
            }
            // A different selection starts a fresh screen
            .id(router.sidebarSelection)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebar: some View {
        @Bindable var router = router
        let sections = store.sections

        return List(selection: $router.sidebarSelection) {
            Section {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(SidebarItem.section(tab))
                }
            }
            tripSection("Happening now", sections.active)
            tripSection("Upcoming", sections.upcoming)
            tripSection("Completed", sections.completed)
        }
        .navigationTitle("RoamPulse")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        router.activeSheet = .createTrip
                    } label: {
                        Label("New Trip", systemImage: "plus")
                    }
                    if store.accountID != nil {
                        Button {
                            router.activeSheet = .joinTrip
                        } label: {
                            Label("Join a Trip", systemImage: "person.2.badge.plus")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add trip")
            }
        }
    }

    @ViewBuilder
    private func tripSection(_ title: String, _ trips: [Trip]) -> some View {
        if !trips.isEmpty {
            Section(title) {
                ForEach(trips) { trip in
                    SidebarTripRow(trip: trip, now: store.now)
                        .tag(SidebarItem.trip(trip.id))
                }
            }
        }
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .trip(let id):
            TripDetailView(viewModel: TripDetailViewModel(tripID: id, store: store, clock: dependencies.clock,
                                                          weather: dependencies.weather))
        case .section(.home):
            HomeView(viewModel: HomeViewModel(store: store, clock: dependencies.clock, weather: dependencies.weather))
                .readableWidth()
        case .section(.trips):
            TripsListView(viewModel: TripsListViewModel(store: store, clock: dependencies.clock,
                                                        weather: dependencies.weather))
                .readableWidth()
        case .section(.journal):
            JournalView(viewModel: JournalViewModel(store: store))
                .readableWidth()
        case .section(.insights):
            InsightsView(viewModel: InsightsViewModel(store: store))
                .readableWidth()
        case .section(.profile):
            ProfileView()
                .readableWidth()
        }
    }
}

extension View {
    // Cards and text read badly stretched across a 13 inch iPad, so lists stay at a comfortable width
    func readableWidth(_ width: CGFloat = 760) -> some View {
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
    }
}

private struct SidebarTripRow: View {
    let trip: Trip
    let now: Date
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            // At very large text the photo gives its room to the trip name
            if !typeSize.isAccessibilitySize {
                TripCoverView(trip: trip, thumbnail: true, showsSymbol: false)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.name)
                    .font(.headline)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(trip.statusText(at: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
