import SwiftUI

struct HomeView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if let trip = store.activeTrip {
                    tripContent(trip)
                } else {
                    noActiveTrip
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Home")
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if let trip = store.currentTrip {
                FloatingActionBar(
                    primaryTitle: "Add Expense",
                    primaryAction: { router.activeSheet = .addExpense(tripID: trip.id) },
                    secondaryTitle: "Record Memory",
                    secondaryAction: { router.activeSheet = .recordMemory }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DemoClock.now.text("EEEE, d MMMM"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(greeting)
                    .font(.largeTitle.bold())
            }
            Spacer()
            Button {
                router.selectedTab = .profile
            } label: {
                Text(store.me.initials)
                    .font(.subheadline.bold())
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let hour = DemoClock.calendar.component(.hour, from: DemoClock.now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - Active trip

    @ViewBuilder
    private func tripContent(_ trip: Trip) -> some View {
        NavigationLink(value: AppRoute.tripDetail(trip.id)) {
            heroCard(trip)
        }
        .buttonStyle(.plain)

        if let advisory = store.weather.advisory {
            NavigationLink(value: AppRoute.weather(trip.id)) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Day \(advisory.day) advisory")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(advisory.shortMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .card()
            }
            .buttonStyle(.plain)
        }

        HStack(spacing: 12) {
            NavigationLink(value: AppRoute.weather(trip.id)) { weatherCard }
            NavigationLink(value: AppRoute.expenses(trip.id)) { budgetCard(trip) }
        }
        .buttonStyle(.plain)

        if let memory = store.latestMemory {
            Button {
                router.activeSheet = .memory(memory.id)
            } label: {
                latestMemoryCard(memory)
            }
            .buttonStyle(.plain)
        }

        quickActions(trip)

        HStack(spacing: 12) {
            if let next = store.upcomingTrips.first {
                NavigationLink(value: AppRoute.tripDetail(next.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Coming Up").font(.subheadline).foregroundStyle(.secondary)
                        Text(next.name).font(.headline).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Text("in \(next.daysUntilStart()) days").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .card()
                }
            }
            NavigationLink(value: AppRoute.packing(trip.id)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Packing").font(.subheadline).foregroundStyle(.secondary)
                    Text("\(trip.packedCount) of \(trip.packing.count)").font(.title2.bold())
                    Spacer(minLength: 0)
                    if trip.packingProgress == 1 {
                        Label("Ready", systemImage: "checkmark.circle").foregroundStyle(.green)
                    } else {
                        Text("\(trip.packingProgress.percentText) packed").foregroundStyle(.secondary)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .card()
            }
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)

        if let balance = trip.balances.first(where: { $0.member.isMe }) {
            NavigationLink(value: AppRoute.expenses(trip.id)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Balances").font(.subheadline).foregroundStyle(.secondary)
                    Text(balance.amount >= 0 ? "You get back \(balance.amount.lkr)" : "You owe \((-balance.amount).lkr)")
                        .font(.headline)
                        .foregroundStyle(balance.amount >= 0 ? .green : .orange)
                }
                .card()
            }
            .buttonStyle(.plain)
        }

        recentExpenses(trip)
    }

    private func heroCard(_ trip: Trip) -> some View {
        ZStack(alignment: .bottomLeading) {
            PhotoView(photo: trip.cover, showsSymbol: false)
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name).font(.title2.bold())
                Text(trip.routeText).foregroundStyle(.white.opacity(0.75))
                if let next = trip.nextActivity() {
                    HStack(spacing: 8) {
                        Text("Next · in \(next.minutes - DemoClock.minutesNow) min").bold()
                        Text("\(next.timeText) \(next.title)").lineLimit(1)
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                }
            }
            .foregroundStyle(.white)
            .padding()
        }
        .frame(height: 230)
        .overlay(alignment: .topLeading) {
            HStack {
                GlassPill(trip.statusText)
                GlassPill("\(store.weather.temperature)° \(store.weather.condition)", icon: store.weather.symbol)
            }
            .font(.caption)
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var weatherCard: some View {
        let weather = store.weather
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(weather.location) Weather").font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Text("\(weather.temperature)°").font(.system(size: 52, weight: .bold))
            Text(weather.condition).font(.subheadline)
            Text("H \(weather.high)° L \(weather.low)°").font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0x2E5A80), Color(hex: 0x1A2E44)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        )
    }

    private func budgetCard(_ trip: Trip) -> some View {
        VStack(spacing: 8) {
            Text("Trip Budget")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            ProgressRing(progress: trip.spentFraction, lineWidth: 10, tint: .blue)
                .frame(width: 64, height: 64)
                .overlay { Text(trip.spentFraction.percentText).font(.caption2.bold()) }
            Text(trip.budgetLeft.lkr).font(.headline)
            Text("left").font(.caption).foregroundStyle(.secondary)
        }
        .frame(minHeight: 170)
        .card()
    }

    private func latestMemoryCard(_ memory: Memory) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Latest Memory").font(.subheadline).foregroundStyle(.secondary)
                Text(memory.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Chip(memory.date.text("HH:mm"))
                    Chip("near \(memory.place)")
                    if let mood = memory.mood {
                        Chip("Reads \(mood.rawValue.lowercased())")
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
            if let photo = memory.photos.first {
                PhotoView(photo: photo)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if memory.photos.count > 1 {
                            Text("+\(memory.photos.count - 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(4)
                        }
                    }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.purple.opacity(0.35), Color.teal.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.stroke))
    }

    private func quickActions(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button { router.activeSheet = .addExpense(tripID: trip.id) } label: {
                    QuickActionTile(icon: "creditcard", tint: .blue, title: "Add Expense")
                }
                Button { router.activeSheet = .recordMemory } label: {
                    QuickActionTile(icon: "mic", tint: .purple, title: "Record Memory")
                }
                NavigationLink(value: AppRoute.tripDetail(trip.id, day: trip.dayNumber())) {
                    QuickActionTile(icon: "list.bullet.rectangle", tint: .primary, title: "Today's Plan")
                }
                Button { router.activeSheet = .addPhoto(memoryID: nil) } label: {
                    QuickActionTile(icon: "photo", tint: .cyan, title: "Add Photo")
                }
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private func recentExpenses(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent Expenses").font(.headline)
                Spacer()
                NavigationLink("View all", value: AppRoute.expenses(trip.id))
                    .font(.subheadline)
            }
            .padding(.bottom, 4)
            let recent = trip.expenses.sorted { $0.date > $1.date }.prefix(2)
            ForEach(Array(recent)) { expense in
                ExpenseRow(expense: expense, showsCategoryIcon: true)
                if expense.id != recent.last?.id { Divider() }
            }
            if recent.isEmpty {
                Text("No expenses yet.").foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: - No active trip

    private var noActiveTrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "suitcase")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            if let next = store.upcomingTrips.first {
                Text("\(next.name) starts in \(next.daysUntilStart()) days")
                    .font(.title3.bold())
                NavigationLink("View trip", value: AppRoute.tripDetail(next.id))
            } else {
                Text("No trips planned yet").font(.title3.bold())
                Text("Create a trip to see your plan, weather and budget here.")
                    .foregroundStyle(.secondary)
            }
            Button("Create Trip") { router.activeSheet = .createTrip }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false, height: 44))
        }
        .card(padding: 20)
    }
}

/// Tile inside the Quick Actions card.
struct QuickActionTile: View {
    let icon: String
    let tint: Color
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(TripStore())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
