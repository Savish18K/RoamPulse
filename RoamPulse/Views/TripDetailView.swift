import SwiftUI

struct TripDetailView: View {
    @State private var viewModel: TripDetailViewModel
    // The map next to the plan on iPad, made when it's first shown
    @State private var mapViewModel: TripMapViewModel?
    @State private var showsSideMap = false
    // Set from the context menu, deleted only after the user confirms
    @State private var activityPendingDelete: Activity?
    // Below this the map column would be too narrow to read, so the plan uses the whole width
    private static let sideMapMinWidth: CGFloat = 760
    @Environment(AppRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.isDetailRoot) private var isDetailRoot
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    init(viewModel: TripDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        if let trip = viewModel.trip {
            // iPad with room to spare: the day plan and a map of the same day side by side
            GeometryReader { proxy in
                let sideBySide = sizeClass == .regular && proxy.size.width >= Self.sideMapMinWidth
                Group {
                    if sideBySide {
                        HStack(spacing: 0) {
                            content(trip)
                                .frame(width: min(proxy.size.width * 0.5, 560))
                            Divider()
                            dayMap(trip)
                        }
                    } else {
                        content(trip)
                    }
                }
                .onChange(of: sideBySide, initial: true) { _, isOn in showsSideMap = isOn }
                // The weather screen on top asked for a day, show it before going back
                .onChange(of: router.dayRequest) { _, request in
                    guard let request, request.tripID == trip.id else { return }
                    viewModel.selectedDay = min(max(request.day, 1), trip.dayCount)
                    router.dayRequest = nil
                }
            }
        } else {
            TripMissingView()
        }
    }

    @ViewBuilder
    private func dayMap(_ trip: Trip) -> some View {
        if let mapViewModel {
            TripMapView(viewModel: mapViewModel, showsDayPicker: false)
                .onChange(of: viewModel.selectedDay, initial: true) { _, day in
                    mapViewModel.selectedDay = day
                }
        } else {
            Color.clear.onAppear {
                mapViewModel = TripMapViewModel(tripID: trip.id, store: dependencies.store, clock: dependencies.clock,
                                                places: dependencies.places)
            }
        }
    }

    private func content(_ trip: Trip) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HeroHeader(photo: trip.cover, trip: trip, pill: viewModel.statusText(for: trip), topInset: proxy.safeAreaInsets.top) {
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
                            return withMotion { viewModel.moveActivity(id, toDayIndex: index) }
                        }
                    )
                    .padding(.horizontal)

                    // Refresh every minute so "NOW" and "Up next" stay right
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
        // On iPad the trip's name is already in the header, so the bar only shows the sidebar button
        .navigationTitle(isDetailRoot ? "" : "Trip Details")
        .navigationBarHiddenOnPhone()
        .toolbar(.hidden, for: .tabBar)
        .task { await viewModel.loadWeather() }
        .confirmationDialog("\(viewModel.deleteTitle)?", isPresented: $viewModel.showDeleteConfirmation, titleVisibility: .visible) {
            Button(viewModel.deleteTitle, role: .destructive) {
                if viewModel.deleteTrip() { dismiss() }
            }
        } message: {
            Text(viewModel.deleteMessage(for: trip))
        }
        .confirmationDialog(
            "Delete this activity?",
            isPresented: Binding(
                get: { activityPendingDelete != nil },
                set: { if !$0 { activityPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: activityPendingDelete
        ) { activity in
            Button("Delete \(activity.title)", role: .destructive) {
                withMotion { viewModel.delete(activity) }
            }
        } message: { _ in
            Text("Its reminder and map pin are removed too.")
        }
    }

    private func tripMenu(_ trip: Trip) -> some View {
        Menu {
            Button {
                router.activeSheet = .editTrip(trip.id)
            } label: {
                Label("Edit Trip", systemImage: "pencil")
            }
            if viewModel.canShare {
                Button {
                    router.activeSheet = .shareTrip(trip.id)
                } label: {
                    Label("Invite Friends", systemImage: "person.2.badge.plus")
                }
            }
            Button(role: .destructive) {
                viewModel.showDeleteConfirmation = true
            } label: {
                Label(viewModel.deleteTitle,
                      systemImage: viewModel.canDeleteForEveryone ? "trash" : "rectangle.portrait.and.arrow.right")
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

    private func tiles(_ trip: Trip) -> some View {
        // One tile per row at very large text so the values aren't cut off
        let columns = typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            NavigationLink(value: AppRoute.packing(trip.id)) {
                StatTile(icon: "bag", tint: .green, title: "Packing", value: viewModel.packingText(for: trip))
            }
            NavigationLink(value: AppRoute.expenses(trip.id)) {
                StatTile(icon: "creditcard", tint: .blue, title: "Expenses", value: viewModel.budgetText(for: trip))
            }
            NavigationLink(value: AppRoute.weather(trip.id, fromTrip: true)) {
                StatTile(icon: "cloud.sun.rain", tint: .cyan, title: "Weather", value: viewModel.weatherText(for: trip))
            }
            NavigationLink(value: AppRoute.journal(trip.id)) {
                StatTile(icon: "waveform", tint: .purple, title: "Journal", value: viewModel.memoriesText(for: trip))
            }
            NavigationLink(value: AppRoute.map(trip.id)) {
                StatTile(icon: "map", tint: .orange, title: "Map", value: viewModel.mapText(for: trip))
            }
        }
        .buttonStyle(.plain)
    }

    private func schedule(_ trip: Trip) -> some View {
        let activities = viewModel.activities
        let next = viewModel.nextActivity

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                AdaptiveStack {
                    Text("Schedule")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(viewModel.selectedDateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
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
                withMotion { viewModel.toggleDone(activity) }
            } label: {
                Image(systemName: activity.isDone ? "checkmark.circle" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(activity.isDone ? .green : (isNext ? .blue : .secondary))
                    // Taller tap area without pushing the row's text down
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .padding(.vertical, -10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(activity.isDone ? "Mark as not done" : "Mark as done")

            Group {
                // iPad shows the activity on the map next to the plan; iPhone opens the map
                if let mapViewModel, showsSideMap {
                    Button {
                        withMotion { mapViewModel.selectedActivityID = activity.id }
                    } label: {
                        activityLabel(activity, isNext: isNext)
                    }
                } else {
                    NavigationLink(value: AppRoute.map(trip.id, activityID: activity.id)) {
                        activityLabel(activity, isNext: isNext)
                    }
                }
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
            return withMotion { viewModel.moveActivity(id, onto: activity) }
        }
        .contextMenu { activityMenu(activity, trip: trip) }
    }

    private func activityLabel(_ activity: Activity, isNext: Bool) -> some View {
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
                Label(advisory.message, systemImage: advisory.icon)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.fill, in: Capsule())
    }

    // Long press menu, also how VoiceOver users reorder
    @ViewBuilder
    private func activityMenu(_ activity: Activity, trip: Trip) -> some View {
        Button {
            router.activeSheet = .editActivity(tripID: trip.id, activityID: activity.id)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button {
            withMotion { viewModel.toggleDone(activity) }
        } label: {
            Label(activity.isDone ? "Mark as not done" : "Mark as done",
                  systemImage: activity.isDone ? "circle" : "checkmark.circle")
        }
        if viewModel.canMoveUp(activity) {
            Button {
                withMotion { viewModel.moveUp(activity) }
            } label: {
                Label("Move earlier", systemImage: "arrow.up")
            }
        }
        if viewModel.canMoveDown(activity) {
            Button {
                withMotion { viewModel.moveDown(activity) }
            } label: {
                Label("Move later", systemImage: "arrow.down")
            }
        }
        if !viewModel.otherDays(for: activity).isEmpty {
            Menu {
                ForEach(viewModel.otherDays(for: activity), id: \.self) { day in
                    Button("Day \(day)") {
                        withMotion { viewModel.move(activity, toDay: day) }
                    }
                }
            } label: {
                Label("Move to another day", systemImage: "calendar")
            }
        }
        Divider()
        Button(role: .destructive) {
            activityPendingDelete = activity
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

                    VStack(alignment: .leading, spacing: 8) {
                        FormField(label: "Place") {
                            TextField(viewModel.placeHint, text: $viewModel.place)
                        }
                        placeSearchResults
                    }
                    // Search after typing stops, a new key press cancels the old one
                    .task(id: viewModel.place) {
                        do {
                            try await Task.sleep(for: .milliseconds(400))
                        } catch {
                            return
                        }
                        await viewModel.searchPlaces()
                    }

                    AdaptiveStack(alignment: .top, spacing: 12) {
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

    // MapKit results for the place, picking one pins the activity on the trip map
    @ViewBuilder
    private var placeSearchResults: some View {
        if let pinned = viewModel.pinnedPlace {
            HStack {
                Label("Pinned on the map", systemImage: "mappin.circle.fill")
                    .foregroundStyle(.green)
                if !pinned.address.isEmpty {
                    Text(pinned.address)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Remove") { viewModel.removePin() }
                    .tapTarget()
            }
            .font(.caption)
        } else if !viewModel.placeResults.isEmpty {
            FlowLayout {
                ForEach(viewModel.placeResults) { place in
                    Button { viewModel.pin(place) } label: {
                        Chip(place.address.isEmpty ? place.name : "\(place.name), \(place.address)", icon: "mappin.and.ellipse")
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Pins this activity on the trip map")
                }
            }
        } else if viewModel.canSearchPlaces && !viewModel.place.trimmed.isEmpty && !viewModel.isSearching {
            Text("Not pinned on the map yet. Pick a result to pin it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

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
                            Button("Use the default list") { withMotion { viewModel.resetToTemplate() } }
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
                    withMotion { viewModel.addItem(named: newItemName, category: addItemCategory) }
                    newItemName = ""
                }
                Button("Cancel", role: .cancel) { newItemName = "" }
            }
            .confirmationDialog("Reset the packing list?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset List", role: .destructive) {
                    withMotion { viewModel.resetToTemplate() }
                }
            } message: {
                Text("The list goes back to the default items, all unpacked. Items you added are removed.")
            }
        } else {
            TripMissingView()
        }
    }

    private func startAddingItem(to category: String) {
        addItemCategory = category
        newItemName = ""
        showAddItem = true
    }

    // e.g. "Rain likely on Day 3 -> Camera rain cover"
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
                        withMotion { viewModel.add(suggestion) }
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
                    withMotion(.snappy) { viewModel.toggle(item) }
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
                        withMotion { viewModel.delete(item) }
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
