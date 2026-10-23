import SwiftUI

/// Home tab: today's trip at a glance, a countdown before a trip, a recap after one,
/// or a welcome when there are no trips yet.
struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @Environment(AppRouter.self) private var router
    @Environment(TripStore.self) private var store

    init(viewModel: HomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        // Redraws every minute so the greeting, countdowns and "Next · in 50 min" stay current.
        TimelineView(.everyMinute) { _ in
            ScrollView {
                VStack(spacing: 14) {
                    header
                    switch viewModel.state {
                    case .noTrips:
                        welcome
                    case .active(let id):
                        if let trip = store.trip(id) { activeContent(trip) }
                    case .upcoming(let id):
                        if let trip = store.trip(id) { upcomingContent(trip) }
                    case .completed(let id):
                        if let trip = store.trip(id) { completedContent(trip) }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .animation(.snappy, value: viewModel.state)
            }
        }
        .background(Theme.background)
        .navigationTitle("Home")
        .toolbar(.hidden, for: .navigationBar)
        .task(id: viewModel.featuredTrip?.id) { await viewModel.loadWeather() }
        .refreshable { await viewModel.loadWeather() }
        .safeAreaInset(edge: .bottom) {
            if let trip = viewModel.currentTrip {
                FloatingActionBar(
                    primaryTitle: "Add Expense",
                    primaryAction: { router.activeSheet = .addExpense(tripID: trip.id) },
                    secondaryTitle: "New Memory",
                    secondaryAction: { router.activeSheet = .newMemory(tripID: trip.id, withPhotos: false) }
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.dateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(viewModel.greeting)
                    .font(.largeTitle.bold())
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button {
                router.selectedTab = .profile
            } label: {
                Text(viewModel.myInitials)
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

    private var welcome: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                PhotoView(photo: .nineArchBridge, showsSymbol: false)
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Plan your first trip").font(.title.bold())
                    Text("Day-by-day plans, shared costs, weather advice and a private journal, all in one place.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityElement(children: .combine)

            VStack(spacing: 10) {
                Button("Create a Trip") { router.activeSheet = .createTrip }
                    .buttonStyle(PrimaryButtonStyle())
                if viewModel.canJoinTrips {
                    Button {
                        router.activeSheet = .joinTrip
                    } label: {
                        Label("Join a Friend's Trip", systemImage: "person.2.badge.plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button("Explore with sample trips") {
                    withAnimation { store.loadSampleData() }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 14) {
                featureRow("calendar", .blue, "Plan day by day", "Activities, effort levels and a packing list that works offline.")
                featureRow("cloud.sun.rain", .cyan, "Weather that knows the plan", "Warnings name the outdoor activity at risk and a better time.")
                featureRow("rectangle.split.2x1", .green, "Split costs fairly", "Balances and the fewest payments to settle up.")
                featureRow("book", .purple, "Keep the memories", "Notes and photos linked to each day, kept on this iPhone.")
            }
            .card(padding: 18)
        }
    }

    private func featureRow(_ icon: String, _ tint: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Theme.fill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func activeContent(_ trip: Trip) -> some View {
        NavigationLink(value: AppRoute.tripDetail(trip.id)) {
            heroCard(trip)
        }
        .buttonStyle(.plain)

        advisoryCard(trip)

        HStack(spacing: 12) {
            NavigationLink(value: AppRoute.weather(trip.id)) { weatherCard(trip) }
            NavigationLink(value: AppRoute.expenses(trip.id)) { budgetCard(trip) }
        }
        .buttonStyle(.plain)

        todaysPlan(trip)

        if let memory = viewModel.latestMemory(in: trip) {
            Button {
                router.activeSheet = .memory(memory.id)
            } label: {
                latestMemoryCard(memory)
            }
            .buttonStyle(.plain)
        } else {
            emptyCard(icon: "book", tint: .purple, title: "No memories yet",
                      text: "Write down today's highlight or add a few photos.",
                      action: "New Memory") {
                router.activeSheet = .newMemory(tripID: trip.id, withPhotos: false)
            }
        }

        quickActions(trip)

        HStack(spacing: 12) {
            if let next = viewModel.nextUpcomingTrip {
                NavigationLink(value: AppRoute.tripDetail(next.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Coming Up").font(.subheadline).foregroundStyle(.secondary)
                        Text(next.name).font(.headline).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Text(viewModel.countdownText(for: next).lowercased()).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .card()
                }
            }
            NavigationLink(value: AppRoute.packing(trip.id)) {
                packingCard(trip)
            }
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)

        if let balance = viewModel.myBalance(in: trip), !trip.expenses.isEmpty {
            NavigationLink(value: AppRoute.expenses(trip.id)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Balances").font(.subheadline).foregroundStyle(.secondary)
                    Text(balanceText(balance.amount))
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
            TripCoverView(trip: trip, showsSymbol: false)
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name).font(.title2.bold())
                Text(trip.routeText).foregroundStyle(.white.opacity(0.75))
                if let next = viewModel.nextActivity(in: trip) {
                    HStack(spacing: 8) {
                        Text(next.countdown).bold()
                        Text(next.detail).lineLimit(1)
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
                GlassPill(viewModel.statusText(for: trip))
                if let weather = viewModel.weather {
                    GlassPill("\(weather.temperature)° \(weather.condition)", icon: weather.symbol)
                }
            }
            .font(.caption)
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the trip")
    }

    @ViewBuilder
    private func advisoryCard(_ trip: Trip) -> some View {
        if let advisory = viewModel.advisory {
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
                    Spacer(minLength: 0)
                }
                .card()
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }

    private func weatherCard(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(trip.mainPlace) Weather").font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            if let weather = viewModel.weather {
                Text("\(weather.temperature)°").font(.system(size: 52, weight: .bold))
                Text(weather.condition).font(.subheadline).lineLimit(1)
                Text(weather.isOffline ? "Offline • from \(weather.updatedAt)" : "H \(weather.high)° L \(weather.low)°")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            } else if let error = viewModel.weatherError {
                Image(systemName: "cloud.slash").font(.title)
                Text(error).font(.caption).lineLimit(4).foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 0)
            } else if !viewModel.forecastIsAvailable(for: trip) {
                Image(systemName: "calendar.badge.clock").font(.title)
                Text(viewModel.forecastNote(for: trip)).font(.caption).foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 0)
            } else {
                ProgressView().tint(.white)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0x2E5A80), Color(hex: 0x1A2E44)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func budgetCard(_ trip: Trip) -> some View {
        VStack(spacing: 8) {
            Text("Trip Budget")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            if trip.budget > 0 {
                ProgressRing(progress: trip.spentFraction, lineWidth: 10,
                             tint: trip.budgetStatus == .onTrack ? .blue : trip.budgetStatus.color)
                    .frame(width: 64, height: 64)
                    .overlay { Text(trip.spentFraction.percentText).font(.caption2.bold()) }
                Text(trip.budgetLeft.lkr).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Text("left").font(.caption).foregroundStyle(.secondary)
            } else {
                Image(systemName: "creditcard").font(.title).foregroundStyle(.secondary).frame(height: 64)
                Text(trip.totalSpent.lkr).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Text("spent • no budget set").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 170)
        .card()
        .accessibilityElement(children: .combine)
    }

    private func todaysPlan(_ trip: Trip) -> some View {
        let activities = viewModel.todaysActivities(in: trip)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's Plan").font(.headline)
                Spacer()
                NavigationLink("Full day", value: AppRoute.tripDetail(trip.id, day: trip.dayNumber(at: viewModel.now)))
                    .font(.subheadline)
            }
            if activities.isEmpty {
                HStack {
                    Text("Nothing planned for today.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Activity") {
                        router.activeSheet = .addActivity(tripID: trip.id, day: trip.dayNumber(at: viewModel.now) ?? 1)
                    }
                    .font(.subheadline.bold())
                }
            } else {
                ForEach(activities.prefix(4)) { activity in
                    HStack(spacing: 10) {
                        Image(systemName: activity.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(activity.isDone ? .green : .secondary)
                        Text(activity.timeText).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        Text(activity.title).font(.subheadline).lineLimit(1)
                            .strikethrough(activity.isDone, color: .secondary)
                        Spacer()
                        if activity.isOutdoor {
                            Image(systemName: "sun.max").font(.caption).foregroundStyle(.orange)
                                .accessibilityLabel("Outdoor")
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if activities.count > 4 {
                    Text("+ \(activities.count - 4) more").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
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
                MemoryPhotoView(photo: photo, thumbnail: true)
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
        .accessibilityElement(children: .combine)
    }

    private func quickActions(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button { router.activeSheet = .addExpense(tripID: trip.id) } label: {
                    QuickActionTile(icon: "creditcard", tint: .blue, title: "Add Expense")
                }
                Button { router.activeSheet = .newMemory(tripID: trip.id, withPhotos: false) } label: {
                    QuickActionTile(icon: "square.and.pencil", tint: .purple, title: "New Memory")
                }
                NavigationLink(value: AppRoute.tripDetail(trip.id, day: trip.dayNumber(at: viewModel.now))) {
                    QuickActionTile(icon: "list.bullet.rectangle", tint: .primary, title: "Today's Plan")
                }
                Button { router.activeSheet = .newMemory(tripID: trip.id, withPhotos: true) } label: {
                    QuickActionTile(icon: "photo.badge.plus", tint: .cyan, title: "Add Photos")
                }
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private func packingCard(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Packing").font(.subheadline).foregroundStyle(.secondary)
            if trip.packing.isEmpty {
                Text("No list yet").font(.headline)
                Spacer(minLength: 0)
                Text("Tap to start one").foregroundStyle(.secondary)
            } else {
                Text("\(trip.packedCount) of \(trip.packing.count)").font(.title2.bold())
                Spacer(minLength: 0)
                if trip.packingProgress == 1 {
                    Label("Ready", systemImage: "checkmark.circle").foregroundStyle(.green)
                } else {
                    Text("\(trip.packingProgress.percentText) packed").foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private func balanceText(_ amount: Double) -> String {
        if abs(amount) < 0.01 { return "You are settled up" }
        return amount > 0 ? "You get back \(amount.lkr)" : "You owe \((-amount).lkr)"
    }

    private func recentExpenses(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent Expenses").font(.headline)
                Spacer()
                if !trip.expenses.isEmpty {
                    NavigationLink("View all", value: AppRoute.expenses(trip.id))
                        .font(.subheadline)
                }
            }
            .padding(.bottom, 4)
            let recent = viewModel.recentExpenses(in: trip)
            ForEach(recent) { expense in
                ExpenseRow(expense: expense, showsCategoryIcon: true)
                if expense.id != recent.last?.id { Divider() }
            }
            if recent.isEmpty {
                HStack {
                    Text("No expenses yet.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Expense") { router.activeSheet = .addExpense(tripID: trip.id) }
                        .font(.subheadline.bold())
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func upcomingContent(_ trip: Trip) -> some View {
        NavigationLink(value: AppRoute.tripDetail(trip.id)) {
            ZStack(alignment: .bottomLeading) {
                TripCoverView(trip: trip, showsSymbol: false)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.countdownText(for: trip))
                        .font(.system(size: 40, weight: .bold))
                        .contentTransition(.numericText())
                    Text(trip.name).font(.title2.bold())
                    Text("\(trip.routeText) • \(trip.dateRangeText)").foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)
                .padding()
            }
            .frame(height: 250)
            .overlay(alignment: .topLeading) {
                GlassPill("Upcoming trip", icon: "airplane.departure").font(.caption).padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the trip")
        }
        .buttonStyle(.plain)

        advisoryCard(trip)

        NavigationLink(value: AppRoute.weather(trip.id)) {
            weatherCard(trip)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.forecastIsAvailable(for: trip))

        let readiness = viewModel.readiness(for: trip)
        VStack(alignment: .leading, spacing: 12) {
            Text("Get ready").font(.headline)
            ForEach(readiness) { item in
                readinessRow(item)
                if item.id != readiness.last?.id { Divider() }
            }
        }
        .card()

        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button { router.activeSheet = .addActivity(tripID: trip.id, day: 1) } label: {
                    QuickActionTile(icon: "calendar.badge.plus", tint: .blue, title: "Add Activity")
                }
                NavigationLink(value: AppRoute.packing(trip.id)) {
                    QuickActionTile(icon: "bag", tint: .green, title: "Packing List")
                }
                if viewModel.canJoinTrips {
                    Button { router.activeSheet = .shareTrip(trip.id) } label: {
                        QuickActionTile(icon: "person.2.badge.plus", tint: .purple, title: "Invite Friends")
                    }
                }
                Button { router.activeSheet = .editTrip(trip.id) } label: {
                    QuickActionTile(icon: "pencil", tint: .orange, title: "Edit Trip")
                }
            }
            .buttonStyle(.plain)
        }
        .card()

        if let next = viewModel.nextUpcomingTrip {
            NavigationLink(value: AppRoute.tripDetail(next.id)) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("After that").font(.subheadline).foregroundStyle(.secondary)
                        Text(next.name).font(.headline)
                    }
                    Spacer()
                    Text(viewModel.countdownText(for: next)).foregroundStyle(.secondary)
                }
                .card()
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func readinessRow(_ item: HomeViewModel.ReadinessItem) -> some View {
        let row = HStack(spacing: 12) {
            Image(systemName: item.isDone ? "checkmark.circle.fill" : item.icon)
                .foregroundStyle(item.isDone ? .green : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if item.route != nil {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isDone ? "Done" : "To do")

        if let route = item.route {
            NavigationLink(value: route) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    @ViewBuilder
    private func completedContent(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                TripCoverView(trip: trip, thumbnail: true)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome back").font(.subheadline).foregroundStyle(.secondary)
                    Text(trip.name).font(.title3.bold())
                    Text(trip.compactDateRange).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack {
                recapStat("\(trip.dayCount)", "days")
                recapStat(trip.totalSpent.compact, "LKR spent")
                recapStat("\(viewModel.memoriesCount(in: trip))", "memories")
                recapStat("\(TripStore.placesVisited(in: [trip]))", "places")
            }
            let photos = viewModel.recapPhotos(for: trip)
            if !photos.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { _, photo in
                        MemoryPhotoView(photo: photo, thumbnail: true)
                            .frame(height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            HStack(spacing: 10) {
                NavigationLink(value: AppRoute.tripDetail(trip.id)) {
                    Text("Open Trip")
                }
                .buttonStyle(SecondaryButtonStyle(height: 44))
                Button("Read Memories") { router.selectedTab = .journal }
                    .buttonStyle(SecondaryButtonStyle(height: 44))
            }
        }
        .card(padding: 18)

        emptyCard(icon: "map", tint: .blue, title: "Where to next?",
                  text: "Plan your next trip and invite your friends.", action: "Create a Trip") {
            router.activeSheet = .createTrip
        }
    }

    private func recapStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// A card that explains what's missing and offers the one action that fills it.
    private func emptyCard(icon: String, tint: Color, title: String, text: String, action: String,
                           perform: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Theme.fill, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
                Button(action, action: perform)
                    .font(.subheadline.bold())
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .card()
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
    let dependencies = AppDependencies.preview()
    NavigationStack {
        HomeView(viewModel: HomeViewModel(store: dependencies.store, clock: dependencies.clock,
                                          weather: dependencies.weather))
    }
    .previewEnvironment(dependencies)
}
