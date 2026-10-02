import SwiftUI

// MARK: - TripDetailView

/// Hub for one trip: summary tiles, day selector and the day's schedule.
struct TripDetailView: View {
    let tripID: UUID
    var initialDay: Int?

    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var selectedDayIndex = 0
    @State private var didSetInitialDay = false

    var body: some View {
        if let trip = store.trip(tripID) {
            content(trip)
        } else {
            ContentUnavailableView("Trip not found", systemImage: "suitcase")
        }
    }

    private func content(_ trip: Trip) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HeroHeader(photo: trip.cover, pill: trip.statusText, topInset: proxy.safeAreaInsets.top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(trip.name).font(.largeTitle.bold())
                            Text("\(trip.destination) • \(trip.dateRangeText) \(trip.endDate.text("yyyy"))")
                                .foregroundStyle(.white.opacity(0.75))
                            HStack(spacing: 10) {
                                AvatarStack(members: trip.members)
                                Text(trip.members.map(\.name).joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .lineLimit(1)
                            }
                        }
                    }

                    tiles(trip)
                        .padding(.horizontal)

                    SegmentedTabs(
                        options: (1...max(trip.dayCount, 1)).map { "Day \($0)" },
                        selection: $selectedDayIndex,
                        dots: Set(trip.advisoryDays.map { $0 - 1 })
                    )
                    .padding(.horizontal)

                    schedule(trip, day: selectedDayIndex + 1)
                        .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom) {
                BackActionBar(actionTitle: "+ Add Activity") {
                    router.activeSheet = .addActivity(tripID: trip.id, day: selectedDayIndex + 1)
                }
            }
        }
        .background(Theme.background)
        .navigationTitle("Trip Details")
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            guard !didSetInitialDay else { return }
            didSetInitialDay = true
            selectedDayIndex = max((initialDay ?? trip.dayNumber() ?? 1) - 1, 0)
        }
    }

    // MARK: - Tiles

    private func tiles(_ trip: Trip) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            NavigationLink(value: AppRoute.packing(trip.id)) {
                StatTile(icon: "bag", tint: .green, title: "Packing",
                         value: "\(trip.packedCount) / \(trip.packing.count) items")
            }
            NavigationLink(value: AppRoute.expenses(trip.id)) {
                StatTile(icon: "creditcard", tint: .blue, title: "Expenses",
                         value: "\(trip.budgetLeft.lkr) left")
            }
            NavigationLink(value: AppRoute.weather(trip.id)) {
                StatTile(icon: "cloud.sun.rain", tint: .cyan, title: "Weather",
                         value: trip.status() == .completed ? "Trip ended"
                            : "\(store.weather.temperature)° • \(store.weather.condition)")
            }
            Button {
                router.selectedTab = .journal
            } label: {
                StatTile(icon: "waveform", tint: .purple, title: "Journal",
                         value: "\(store.memories(inTrip: trip.id).count) memories")
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Schedule

    private func schedule(_ trip: Trip, day: Int) -> some View {
        let activities = trip.activities(onDay: day)
        let isToday = trip.dayNumber() == day
        let next = isToday ? trip.nextActivity() : nil

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Schedule").font(.title2.bold())
                Text(trip.date(ofDay: day).text("EEE d MMM"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let intensity = trip.intensity(ofDay: day) {
                    Text(intensity.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(intensity.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(Capsule().strokeBorder(intensity.color))
                }
            }

            if activities.isEmpty {
                Text("Nothing planned yet. Tap “+ Add Activity” to start this day.")
                    .foregroundStyle(.secondary)
                    .card()
            }

            ForEach(activities) { activity in
                if isToday && activity.id == next?.id {
                    nowLine
                }
                activityRow(activity, trip: trip, isNext: activity.id == next?.id)
            }

            if isToday && next == nil && !activities.isEmpty {
                nowLine
            }
        }
    }

    private var nowLine: some View {
        HStack(spacing: 10) {
            Circle().fill(.blue).frame(width: 12, height: 12)
            Text("NOW • \(DemoClock.minutesNow.clockText)")
                .font(.subheadline.bold())
                .foregroundStyle(.blue)
            Rectangle().fill(.blue).frame(height: 1)
        }
    }

    private func activityRow(_ activity: Activity, trip: Trip, isNext: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation { store.toggleDone(activity.id, in: trip.id) }
            } label: {
                Image(systemName: activity.isDone ? "checkmark.circle" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(activity.isDone ? .green : (isNext ? .blue : .secondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(activity.isDone ? "Mark as not done" : "Mark as done")

            NavigationLink(value: AppRoute.offlineMap(trip.id, activityID: activity.id)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(statusText(activity, isNext: isNext))
                            .foregroundStyle(isNext ? .blue : .secondary)
                            .fontWeight(isNext ? .semibold : .regular)
                        if activity.isOutdoor {
                            Text("Outdoor")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.fill, in: Capsule())
                        }
                    }
                    .font(.subheadline)
                    Text(activity.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let advisory = activity.advisory {
                        Label(advisory, systemImage: "cloud.heavyrain")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func statusText(_ activity: Activity, isNext: Bool) -> String {
        if activity.isDone { return "\(activity.timeText) • Done" }
        if isNext { return "\(activity.timeText) • Up next" }
        return activity.timeText
    }
}

#Preview {
    NavigationStack { TripDetailView(tripID: SampleData.hillCountry.id) }
        .environment(TripStore())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}

// MARK: - AddActivityView

struct AddActivityView: View {
    let tripID: UUID
    let day: Int

    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var place = ""
    @State private var time = DemoClock.date(2026, 12, 13, 19, 30)
    @State private var effortIndex = 1
    @State private var isOutdoor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    FormField(label: "Activity Name") {
                        TextField("Dinner in Ella town", text: $title)
                    }

                    FormField(label: "Place") {
                        TextField("Ella", text: $place)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Time")
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, -6)
                            .fieldStyle()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Physical Effort")
                        SegmentedTabs(options: Effort.allCases.map(\.rawValue), selection: $effortIndex)
                    }

                    Toggle(isOn: $isOutdoor) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Outdoor Activity").font(.headline)
                            Text("Adapts recommendations to weather forecast.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Add Activity", action: add)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .navigationTitle("Add Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Add Activity").font(.headline)
                        Text("Day \(day)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    private func add() {
        let parts = DemoClock.calendar.dateComponents([.hour, .minute], from: time)
        let activity = Activity(
            day: day,
            title: title.trimmingCharacters(in: .whitespaces),
            minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0),
            place: place.isEmpty ? (store.trip(tripID)?.destination ?? "") : place,
            effort: Effort.allCases[effortIndex],
            isOutdoor: isOutdoor
        )
        store.addActivity(activity, to: tripID)
        dismiss()
    }
}

// MARK: - PackingView

struct PackingView: View {
    let tripID: UUID
    @Environment(TripStore.self) private var store

    private let suggestedItem = "Camera rain cover"

    var body: some View {
        if let trip = store.trip(tripID) {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        Label("\(trip.packedCount) / \(trip.packing.count) packed",
                              systemImage: trip.packingProgress == 1 ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.subheadline.bold())
                            .foregroundStyle(trip.packingProgress == 1 ? .green : .secondary)
                    }

                    if showsRainSuggestion(trip) {
                        rainSuggestion
                    }

                    ProgressRing(progress: trip.packingProgress, lineWidth: 9)
                        .frame(width: 84, height: 84)
                        .overlay { Text(trip.packingProgress.percentText).font(.subheadline.bold()) }
                        .padding(.vertical, 4)

                    ForEach(categories(in: trip), id: \.self) { category in
                        categoryCard(category, trip: trip)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Packing")
            .sensoryFeedback(.selection, trigger: trip.packedCount)
        }
    }

    private func showsRainSuggestion(_ trip: Trip) -> Bool {
        !trip.advisoryDays.isEmpty && !trip.packing.contains { $0.name == suggestedItem }
    }

    private var rainSuggestion: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.rain")
                .font(.title2)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rain likely on Mon 14 Dec (Day 3)").font(.subheadline.bold())
                Text("90% chance from 14:00 to 17:00. Add a rain cover for the camera?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("+ Add") {
                withAnimation { store.addPackingItem(suggestedItem, category: "Rain Gear", to: tripID) }
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: false, height: 34))
        }
        .padding(14)
        .background(Color.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cyan.opacity(0.4)))
    }

    private func categories(in trip: Trip) -> [String] {
        let used = Set(trip.packing.map(\.category))
        let known = SampleData.packingCategories.filter(used.contains)
        let extra = used.subtracting(known).sorted()
        return known + extra
    }

    private func categoryCard(_ category: String, trip: Trip) -> some View {
        let items = trip.packing.filter { $0.category == category }
        return VStack(alignment: .leading, spacing: 0) {
            Text(category)
                .font(.headline)
                .padding(.bottom, 6)
            ForEach(items) { item in
                Button {
                    withAnimation(.snappy) { store.togglePacked(item.id, in: tripID) }
                } label: {
                    HStack {
                        Text(item.name)
                            .foregroundStyle(item.isPacked ? .primary : .secondary)
                        Spacer()
                        Image(systemName: item.isPacked ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(item.isPacked ? .green : .secondary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(item.isPacked ? "Packed" : "Not packed")

                if item.id != items.last?.id {
                    Divider()
                }
            }
        }
        .card()
    }
}

#Preview {
    NavigationStack { PackingView(tripID: SampleData.hillCountry.id) }
        .environment(TripStore())
        .preferredColorScheme(.dark)
}
