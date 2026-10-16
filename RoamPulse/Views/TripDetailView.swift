import SwiftUI

// MARK: - TripDetailView

/// Hub for one trip: summary tiles, day tabs and the day's schedule.
struct TripDetailView: View {
    @State private var viewModel: TripDetailViewModel
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    init(viewModel: TripDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        if let trip = viewModel.trip {
            content(trip)
        } else {
            ContentUnavailableView("Trip not found", systemImage: "suitcase")
        }
    }

    private func content(_ trip: Trip) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HeroHeader(photo: trip.cover, pill: viewModel.statusText(for: trip), topInset: proxy.safeAreaInsets.top) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(trip.name).font(.largeTitle.bold())
                                Text(viewModel.subtitle(for: trip))
                                    .foregroundStyle(.white.opacity(0.75))
                                HStack(spacing: 10) {
                                    AvatarStack(members: trip.members)
                                    Text(trip.members.map(\.name).joined(separator: ", "))
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.75))
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                            tripMenu(trip)
                        }
                    }

                    tiles(trip)
                        .padding(.horizontal)

                    SegmentedTabs(
                        options: viewModel.dayTitles,
                        selection: $viewModel.selectedDayIndex,
                        dots: viewModel.advisoryDayIndexes,
                        onDrop: { index, items in
                            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                            return withAnimation { viewModel.moveActivity(id, toDayIndex: index) }
                        }
                    )
                    .padding(.horizontal)

                    // Redraws every minute so the "NOW" line and "Up next" stay current.
                    TimelineView(.everyMinute) { _ in
                        schedule(trip)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom) {
                BackActionBar(actionTitle: "+ Add Activity") {
                    router.activeSheet = .addActivity(tripID: trip.id, day: viewModel.selectedDay)
                }
            }
        }
        .background(Theme.background)
        .navigationTitle("Trip Details")
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await viewModel.loadWeather() }
        .confirmationDialog("Delete \(trip.name)?", isPresented: $viewModel.showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Trip", role: .destructive) {
                if viewModel.deleteTrip() { dismiss() }
            }
        } message: {
            Text("Its itinerary, packing list, expenses and memories will be removed from this iPhone.")
        }
    }

    private func tripMenu(_ trip: Trip) -> some View {
        Menu {
            Button {
                router.activeSheet = .editTrip(trip.id)
            } label: {
                Label("Edit Trip", systemImage: "pencil")
            }
            Button(role: .destructive) {
                viewModel.showDeleteConfirmation = true
            } label: {
                Label("Delete Trip", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel("Trip options")
    }

    // MARK: - Tiles

    private func tiles(_ trip: Trip) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            NavigationLink(value: AppRoute.packing(trip.id)) {
                StatTile(icon: "bag", tint: .green, title: "Packing", value: viewModel.packingText(for: trip))
            }
            NavigationLink(value: AppRoute.expenses(trip.id)) {
                StatTile(icon: "creditcard", tint: .blue, title: "Expenses", value: viewModel.budgetText(for: trip))
            }
            NavigationLink(value: AppRoute.weather(trip.id)) {
                StatTile(icon: "cloud.sun.rain", tint: .cyan, title: "Weather", value: viewModel.weatherText(for: trip))
            }
            Button {
                router.selectedTab = .journal
            } label: {
                StatTile(icon: "waveform", tint: .purple, title: "Journal", value: viewModel.memoriesText(for: trip))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Schedule

    private func schedule(_ trip: Trip) -> some View {
        let activities = viewModel.activities
        let next = viewModel.nextActivity

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Schedule").font(.title2.bold())
                    Text(viewModel.selectedDateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let intensity = viewModel.intensity {
                        Label(intensity.title, systemImage: intensity.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(intensity.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(Capsule().strokeBorder(intensity.color))
                    }
                }
                if let advice = viewModel.intensityAdvice {
                    Text(advice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if activities.count > 1 {
                    Text("Hold an activity to drag it, or for more options.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if activities.isEmpty {
                Text("Nothing planned yet. Tap “+ Add Activity” to start this day.")
                    .foregroundStyle(.secondary)
                    .card()
            }

            ForEach(activities) { activity in
                if viewModel.isToday && activity.id == next?.id {
                    nowLine
                }
                activityRow(activity, trip: trip, isNext: activity.id == next?.id)
            }

            if viewModel.isToday && next == nil && !activities.isEmpty {
                nowLine
            }
        }
    }

    private var nowLine: some View {
        HStack(spacing: 10) {
            Circle().fill(.blue).frame(width: 12, height: 12)
            Text(viewModel.nowText)
                .font(.subheadline.bold())
                .foregroundStyle(.blue)
            Rectangle().fill(.blue).frame(height: 1)
        }
    }

    private func activityRow(_ activity: Activity, trip: Trip, isNext: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation { viewModel.toggleDone(activity) }
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
                        Text(viewModel.statusText(for: activity))
                            .foregroundStyle(isNext ? .blue : .secondary)
                            .fontWeight(isNext ? .semibold : .regular)
                        if activity.isOutdoor {
                            tag("Outdoor")
                        }
                        if activity.effort == .high {
                            tag("High effort")
                        }
                    }
                    .font(.subheadline)
                    Text(activity.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let advisory = viewModel.advisory(for: activity) {
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
        .contentShape(Rectangle())
        .draggable(activity.id.uuidString) {
            Text(activity.title)
                .font(.headline)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            return withAnimation { viewModel.moveActivity(id, onto: activity) }
        }
        .contextMenu { activityMenu(activity, trip: trip) }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.fill, in: Capsule())
    }

    /// Long-press menu. Also the accessible way to reorder and move, since VoiceOver can't drag.
    @ViewBuilder
    private func activityMenu(_ activity: Activity, trip: Trip) -> some View {
        Button {
            router.activeSheet = .editActivity(tripID: trip.id, activityID: activity.id)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button {
            withAnimation { viewModel.toggleDone(activity) }
        } label: {
            Label(activity.isDone ? "Mark as not done" : "Mark as done",
                  systemImage: activity.isDone ? "circle" : "checkmark.circle")
        }
        if viewModel.canMoveUp(activity) {
            Button {
                withAnimation { viewModel.moveUp(activity) }
            } label: {
                Label("Move earlier", systemImage: "arrow.up")
            }
        }
        if viewModel.canMoveDown(activity) {
            Button {
                withAnimation { viewModel.moveDown(activity) }
            } label: {
                Label("Move later", systemImage: "arrow.down")
            }
        }
        if !viewModel.otherDays(for: activity).isEmpty {
            Menu {
                ForEach(viewModel.otherDays(for: activity), id: \.self) { day in
                    Button("Day \(day)") {
                        withAnimation { viewModel.move(activity, toDay: day) }
                    }
                }
            } label: {
                Label("Move to another day", systemImage: "calendar")
            }
        }
        Divider()
        Button(role: .destructive) {
            withAnimation { viewModel.delete(activity) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        TripDetailView(viewModel: TripDetailViewModel(tripID: dependencies.previewTripID, store: dependencies.store,
                                                      clock: dependencies.clock, weather: dependencies.weather))
    }
    .previewEnvironment(dependencies)
}

// MARK: - ActivityFormView

/// Add Activity and Edit Activity.
struct ActivityFormView: View {
    @State private var viewModel: ActivityFormViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    init(viewModel: ActivityFormViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    FormField(label: "Activity Name") {
                        TextField("Dinner in Ella town", text: $viewModel.title)
                    }

                    FormField(label: "Place") {
                        TextField(viewModel.placeHint, text: $viewModel.place)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Day")
                            Picker("Day", selection: $viewModel.day) {
                                ForEach(1...viewModel.dayCount, id: \.self) { day in
                                    Text("Day \(day)").tag(day)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, -6)
                            .fieldStyle()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Time")
                            DatePicker("Time", selection: $viewModel.time, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, -6)
                                .fieldStyle()
                        }
                    }

                    if let warning = viewModel.clashWarning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Physical Effort")
                        SegmentedTabs(options: Effort.allCases.map(\.rawValue), selection: $viewModel.effortIndex)
                    }

                    Toggle(isOn: $viewModel.isOutdoor) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Outdoor Activity").font(.headline)
                            Text("Adapts recommendations to weather forecast.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)

                    if viewModel.isEditing {
                        Button("Delete Activity", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button(viewModel.saveTitle) {
                    if viewModel.save() { dismiss() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canSave)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(viewModel.screenTitle).font(.headline)
                        Text("Day \(viewModel.day)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .confirmationDialog("Delete this activity?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if viewModel.delete() { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }
}

// MARK: - PackingView

struct PackingView: View {
    @State private var viewModel: PackingViewModel
    @State private var showAddItem = false
    @State private var addItemCategory = "Extras"
    @State private var newItemName = ""
    @State private var confirmReset = false

    init(viewModel: PackingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        if let trip = viewModel.trip {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        Label(viewModel.packedText,
                              systemImage: viewModel.isComplete ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.subheadline.bold())
                            .foregroundStyle(viewModel.isComplete ? .green : .secondary)
                    }

                    if !viewModel.suggestions.isEmpty {
                        suggestionsCard
                    }

                    ProgressRing(progress: viewModel.progress, lineWidth: 9)
                        .frame(width: 84, height: 84)
                        .overlay { Text(viewModel.progress.percentText).font(.subheadline.bold()) }
                        .padding(.vertical, 4)
                        .accessibilityElement()
                        .accessibilityLabel("Packing progress")
                        .accessibilityValue(viewModel.progress.percentText)

                    ForEach(viewModel.categories, id: \.self) { category in
                        categoryCard(category)
                    }

                    if trip.packing.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing to pack yet", systemImage: "bag")
                        } actions: {
                            Button("Use the default list") { withAnimation { viewModel.resetToTemplate() } }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Packing")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            startAddingItem(to: "Extras")
                        } label: {
                            Label("Add item", systemImage: "plus")
                        }
                        Button(role: .destructive) {
                            confirmReset = true
                        } label: {
                            Label("Reset to default list", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Packing options")
                }
            }
            .sensoryFeedback(.selection, trigger: trip.packedCount)
            .task { await viewModel.loadWeather() }
            .alert("Add to \(addItemCategory)", isPresented: $showAddItem) {
                TextField("Item name", text: $newItemName)
                Button("Add") {
                    withAnimation { viewModel.addItem(named: newItemName, category: addItemCategory) }
                    newItemName = ""
                }
                Button("Cancel", role: .cancel) { newItemName = "" }
            }
            .confirmationDialog("Reset the packing list?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset List", role: .destructive) {
                    withAnimation { viewModel.resetToTemplate() }
                }
            } message: {
                Text("The list goes back to the default items, all unpacked. Items you added are removed.")
            }
        }
    }

    private func startAddingItem(to category: String) {
        addItemCategory = category
        newItemName = ""
        showAddItem = true
    }

    /// Weather and itinerary suggestions, like "Rain likely on Day 3 → Camera rain cover".
    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Suggested for this trip", systemImage: "sparkles")
                .font(.subheadline.bold())
            ForEach(viewModel.suggestions) { suggestion in
                HStack(spacing: 12) {
                    Image(systemName: suggestion.icon)
                        .font(.title3)
                        .foregroundStyle(.cyan)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.item).font(.subheadline.bold())
                        Text(suggestion.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("+ Add") {
                        withAnimation { viewModel.add(suggestion) }
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false, height: 34))
                    .accessibilityLabel("Add \(suggestion.item)")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cyan.opacity(0.4)))
    }

    private func categoryCard(_ category: String) -> some View {
        let items = viewModel.items(in: category)
        return VStack(alignment: .leading, spacing: 0) {
            Text(category)
                .font(.headline)
                .padding(.bottom, 6)
            ForEach(items) { item in
                Button {
                    withAnimation(.snappy) { viewModel.toggle(item) }
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
                .contextMenu {
                    Button(role: .destructive) {
                        withAnimation { viewModel.delete(item) }
                    } label: {
                        Label("Remove from list", systemImage: "trash")
                    }
                }

                Divider()
            }
            Button {
                startAddingItem(to: category)
            } label: {
                Label("Add item", systemImage: "plus")
                    .font(.subheadline)
                    .padding(.top, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .card()
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        PackingView(viewModel: PackingViewModel(tripID: dependencies.previewTripID, store: dependencies.store,
                                                weather: dependencies.weather))
    }
    .previewEnvironment(dependencies)
}
