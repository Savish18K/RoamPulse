import Charts
import SwiftUI

// Numbers come from TravelStats
struct StatisticsView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var range = 0

    // Rough LKR to USD rate
    private let usdRate = 300.3

    private var thisYear: Int { Calendar.trip.component(.year, from: store.now) }

    private var stats: TravelStats {
        TravelStats.make(trips: store.trips, memories: store.memories, now: store.now,
                         period: range == 0 ? .year(thisYear) : .allTime)
    }

    var body: some View {
        let stats = stats
        ScrollView {
            VStack(spacing: 14) {
                SegmentedTabs(options: [String(thisYear), "All time"], selection: $range)

                if stats.isEmpty {
                    ContentUnavailableView {
                        Label("No trips yet", systemImage: "chart.bar.xaxis")
                    } description: {
                        Text(range == 0 ? "Trips that start in \(String(thisYear)) appear here once they begin."
                                        : "Your statistics appear once your first trip begins.")
                    }
                    .padding(.top, 30)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        tile("Trips", "\(stats.tripCount)")
                        tile("Days", "\(stats.daysTravelled)")
                        tile("Places", "\(stats.places)")
                        tile("Memories", "\(stats.memories)")
                    }
                    landmarksCard(stats)
                    spendingCard(stats)
                    if stats.byTrip.count > 1 {
                        perTripCard(stats)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Explore travel memories").foregroundStyle(.secondary)
                        Button("Read the year back in Insights") { router.selectedTab = .insights }
                            .font(.headline)
                    }
                    .card()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Statistics")
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.largeTitle.bold()).contentTransition(.numericText())
        }
        .card(padding: 18)
        .accessibilityElement(children: .combine)
    }

    private func landmarksCard(_ stats: TravelStats) -> some View {
        let catalogue = store.landmarks
        let found = catalogue.filter { stats.landmarks.contains($0.name) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Landmarks visited").foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "building.columns").foregroundStyle(.purple)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(found.count)").font(.largeTitle.bold())
                Text("of \(catalogue.count) Sri Lankan landmarks").foregroundStyle(.secondary)
            }
            ProgressView(value: Double(found.count), total: Double(max(catalogue.count, 1)))
                .tint(.purple)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(found) { landmark in
                        PhotoView(photo: landmark.photo)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityLabel(landmark.name)
                    }
                    if found.count < catalogue.count {
                        Text("\(catalogue.count - found.count) more to find")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 56)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .card(padding: 18)
    }

    private func spendingCard(_ stats: TravelStats) -> some View {
        let categories = ExpenseCategory.allCases.filter { (stats.byCategory[$0] ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Total Spending").foregroundStyle(.secondary)
                Spacer()
                if stats.hasBudget {
                    Label(stats.isOnBudget ? "On Budget" : "Over Budget",
                          systemImage: stats.isOnBudget ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(stats.isOnBudget ? .green : .orange)
                }
            }
            Text(stats.totalSpent.lkr)
                .font(.system(size: 40, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("~ USD \((stats.totalSpent / usdRate).grouped) • \(stats.averagePerDay.lkr) a day")
                .foregroundStyle(.secondary)

            if categories.isEmpty {
                Text("No expenses recorded yet.").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 18) {
                    Chart(categories) { category in
                        SectorMark(angle: .value("Spent", stats.byCategory[category] ?? 0),
                                   innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(category.color)
                            .accessibilityLabel(category.rawValue)
                            .accessibilityValue((stats.byCategory[category] ?? 0).lkr)
                    }
                    .frame(width: 120, height: 120)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(categories) { category in
                            HStack(spacing: 6) {
                                Circle().fill(category.color).frame(width: 8, height: 8)
                                Text(category.rawValue).font(.subheadline)
                                Spacer()
                                Text((stats.byCategory[category] ?? 0).compact)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .card(padding: 18)
    }

    private func perTripCard(_ stats: TravelStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Trip").foregroundStyle(.secondary)
            Chart(stats.byTrip) { trip in
                ForEach(ExpenseCategory.allCases) { category in
                    BarMark(x: .value("Spent", trip.byCategory[category] ?? 0),
                            y: .value("Trip", trip.name))
                        .foregroundStyle(by: .value("Category", category.rawValue))
                }
            }
            .chartForegroundStyleScale(domain: ExpenseCategory.allCases.map(\.rawValue),
                                       range: ExpenseCategory.allCases.map(\.color))
            .chartLegend(position: .bottom)
            .frame(height: CGFloat(60 * stats.byTrip.count + 40))
            .accessibilityLabel("Spending per trip, by category")
        }
        .card(padding: 18)
    }
}

#Preview {
    NavigationStack { StatisticsView() }
        .previewEnvironment(.preview())
}
