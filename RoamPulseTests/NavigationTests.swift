import Foundation
import Testing
@testable import RoamPulse

// The router keeps the iPhone tabs and the iPad sidebar pointing at the same place
@MainActor
struct NavigationTests {
    @Test func openingATripSelectsItInTheSidebarAndTheTripsTab() {
        let router = AppRouter()
        let id = UUID()
        router.openTrip(id)
        #expect(router.selectedTab == .trips)
        #expect(router.tripsPath == [.tripDetail(id)])
        #expect(router.sidebarSelection == .trip(id))
    }

    @Test func switchingTabsMovesTheSidebarAndBack() {
        let router = AppRouter()
        router.selectedTab = .journal
        #expect(router.sidebarSelection == .section(.journal))

        router.sidebarSelection = .section(.insights)
        #expect(router.selectedTab == .insights)
    }

    @Test func aNewSidebarSelectionStartsAFreshDetailScreen() {
        let router = AppRouter()
        router.detailPath = [.statistics, .settings]
        router.sidebarSelection = .trip(UUID())
        #expect(router.detailPath.isEmpty)
    }

    @Test func searchingInsightsWorksOnBothLayouts() {
        let router = AppRouter()
        router.searchInsights(for: "Ella")
        #expect(router.selectedTab == .insights)
        #expect(router.sidebarSelection == .section(.insights))
        #expect(router.insightsSearch == "Ella")
    }
}
