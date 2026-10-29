import PhotosUI
import SwiftUI

struct TripsListView: View {
    @State private var viewModel: TripsListViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: TripsListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !viewModel.activeTrips.isEmpty {
                    sectionTitle(viewModel.activeTrips.count == 1 ? "Active Trip" : "Active Trips")
                    ForEach(viewModel.activeTrips) { trip in
                        NavigationLink(value: AppRoute.tripDetail(trip.id)) {
                            ActiveTripCard(trip: trip, statusText: viewModel.statusText(for: trip), weather: viewModel.weather[trip.id])
                        }
                        .buttonStyle(.plain)
                        .contextMenu { tripMenu(trip) }
                    }
                }

                if !viewModel.upcomingTrips.isEmpty {
                    sectionTitle("Upcoming")
                    tripGroup(viewModel.upcomingTrips, subtitle: viewModel.upcomingSubtitle)
                }

                if !viewModel.completedTrips.isEmpty {
                    sectionTitle("Completed")
                    tripGroup(viewModel.completedTrips, subtitle: viewModel.completedSubtitle)
                }

                if viewModel.hasNoTrips {
                    ContentUnavailableView("No trips yet", systemImage: "suitcase",
                                           description: Text("Tap Create Trip to plan your first trip."))
                } else if viewModel.hasNoSearchResults {
                    ContentUnavailableView.search(text: viewModel.searchText)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Trips")
        .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search trips, places or memories...")
        .safeAreaInset(edge: .bottom) {
            FloatingActionBar(primaryTitle: "Create Trip", primaryAction: { router.activeSheet = .createTrip })
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.activeSheet = .joinTrip
                } label: {
                    Label("Join Trip", systemImage: "person.2.badge.plus")
                }
                .accessibilityHint("Join a friend's trip with an invite code")
            }
        }
        .confirmationDialog(
            "Delete this trip?",
            isPresented: Binding(
                get: { viewModel.tripPendingDelete != nil },
                set: { if !$0 { viewModel.tripPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.tripPendingDelete
        ) { trip in
            Button("Delete \(trip.name)", role: .destructive) {
                withMotion { viewModel.confirmDelete() }
            }
        } message: { _ in
            Text("Its itinerary, packing list, expenses and memories will be removed from this \(Device.name).")
        }
        .task(id: viewModel.activeTrips.map(\.id)) { await viewModel.loadWeather() }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .padding(.top, 6)
    }

    private func tripGroup(_ trips: [Trip], subtitle: @escaping (Trip) -> String) -> some View {
        VStack(spacing: 0) {
            ForEach(trips) { trip in
                NavigationLink(value: AppRoute.tripDetail(trip.id)) {
                    HStack(spacing: 14) {
                        TripCoverView(trip: trip, thumbnail: true)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(trip.name).font(.headline)
                            Text(subtitle(trip)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { tripMenu(trip) }

                if trip.id != trips.last?.id {
                    Divider().padding(.leading, 84)
                }
            }
        }
        .card(padding: 0)
    }

    @ViewBuilder
    private func tripMenu(_ trip: Trip) -> some View {
        Button {
            router.activeSheet = .editTrip(trip.id)
        } label: {
            Label("Edit Trip", systemImage: "pencil")
        }
        Button(role: .destructive) {
            viewModel.requestDelete(trip)
        } label: {
            Label("Delete Trip", systemImage: "trash")
        }
    }
}

struct ActiveTripCard: View {
    let trip: Trip
    let statusText: String
    let weather: WeatherSnapshot?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                TripCoverView(trip: trip, showsSymbol: false)
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.name).font(.title.bold())
                    Text(trip.dateRangeText).foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .frame(height: 220)
            .overlay(alignment: .top) {
                HStack {
                    GlassPill(statusText)
                    Spacer()
                    if let weather {
                        GlassPill("\(weather.temperature)° • \(weather.location)")
                    }
                }
                .padding(16)
            }

            HStack {
                AvatarStack(members: trip.members)
                Spacer()
                Text("\(trip.destination) • \(trip.members.count) members")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Theme.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.stroke))
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        TripsListView(viewModel: TripsListViewModel(store: dependencies.store, clock: dependencies.clock,
                                                    weather: dependencies.weather))
    }
    .previewEnvironment(dependencies)
}

struct TripFormView: View {
    @State private var viewModel: TripFormViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(ReminderService.self) private var reminders

    @State private var showDatePickers = false
    @State private var showAddCompanion = false
    @State private var memberToRemove: Member?
    @State private var pickedCover: PhotosPickerItem?

    init(viewModel: TripFormViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    FormField(label: "Trip Name") {
                        TextField("Southern Coast Weekend", text: $viewModel.name)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        FormField(label: "Destination") {
                            TextField("Galle", text: $viewModel.destination)
                        }
                        FlowLayout {
                            if viewModel.placeSuggestions.isEmpty {
                                ForEach(viewModel.destinationSuggestions, id: \.self) { place in
                                    Button { viewModel.destination = place } label: {
                                        Chip(place, isSelected: viewModel.destination == place)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                ForEach(viewModel.placeSuggestions) { place in
                                    Button { viewModel.pick(place) } label: {
                                        Chip("\(place.name), \(place.region)", icon: "mappin.and.ellipse")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Sets the destination and its location for the weather")
                                }
                            }
                        }
                        if let picked = viewModel.pickedPlace {
                            Label("\(picked.name), \(picked.region)", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    // Search after typing stops, a new key press cancels the old one
                    .task(id: viewModel.destination) {
                        do {
                            try await Task.sleep(for: .milliseconds(400))
                        } catch {
                            return
                        }
                        await viewModel.searchPlaces()
                    }

                    coverSection

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Dates")
                            Button {
                                withMotion { showDatePickers.toggle() }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(viewModel.dateRangeText).font(.headline).foregroundStyle(.primary)
                                    Text(viewModel.datesAreValid ? "\(viewModel.dayCount) days calculated" : "Check the dates")
                                        .font(.caption)
                                        .foregroundStyle(viewModel.datesAreValid ? .green : .red)
                                }
                                .fieldStyle()
                            }
                            .buttonStyle(.plain)
                        }
                        FormField(label: "Budget") {
                            HStack(spacing: 6) {
                                Text("LKR").foregroundStyle(.secondary)
                                TextField("90,000", text: $viewModel.budgetText)
                                    .keyboardType(.decimalPad)
                                    .font(.headline)
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    if showDatePickers {
                        VStack(spacing: 4) {
                            DatePicker("Start", selection: $viewModel.startDate, displayedComponents: .date)
                            DatePicker("End", selection: $viewModel.endDate, displayedComponents: .date)
                        }
                        .fieldStyle()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    companionsSection

                    Toggle(isOn: $viewModel.remindersOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bedtime & packing reminders").font(.headline)
                            Text("Auto-ping scheduled tasks").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)

                    if !viewModel.datesAreValid {
                        message("The end date must be on or after the start date.", color: .red)
                    }
                    if let warning = viewModel.shortenedTripWarning {
                        message(warning, color: .orange)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button(viewModel.saveTitle) {
                    if viewModel.save() {
                        // First trip with reminders on asks for permission
                        if viewModel.remindersOn {
                            Task { await reminders.requestPermissionIfNeeded() }
                        }
                        dismiss()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canSave || viewModel.isPreparingCover)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Add companion", isPresented: $showAddCompanion) {
                TextField("Name", text: $viewModel.newCompanionName)
                Button("Add") { viewModel.addCompanion() }
                Button("Cancel", role: .cancel) { viewModel.newCompanionName = "" }
            }
            .confirmationDialog(
                "Remove \(memberToRemove?.name ?? "companion")?",
                isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }),
                titleVisibility: .visible,
                presenting: memberToRemove
            ) { member in
                Button("Remove \(member.name)", role: .destructive) {
                    withMotion { viewModel.remove(member) }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    // PhotosPicker only shares the picked photo, resized and saved on Save
    private var coverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Cover Photo")
            HStack(spacing: 14) {
                coverPreview
                    .frame(width: 84, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        if viewModel.isPreparingCover {
                            ProgressView()
                        }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    // Worked out here because the label closure can run off the main thread
                    let pickerTitle = viewModel.hasCustomCover ? "Change photo" : "Choose a photo"
                    PhotosPicker(selection: $pickedCover, matching: .images, preferredItemEncoding: .compatible) {
                        Label(pickerTitle, systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                    }
                    if viewModel.hasCustomCover {
                        Button("Use the default photo", role: .destructive) {
                            pickedCover = nil
                            withMotion { viewModel.removeCoverPhoto() }
                        }
                        .font(.subheadline)
                    }
                }
                Spacer(minLength: 0)
            }
            .fieldStyle()
            if let problem = viewModel.coverProblem {
                Text(problem).font(.caption).foregroundStyle(.red)
            } else {
                Text("Kept on this \(Device.name) only. Your other devices show a photo of the destination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: pickedCover) { _, item in
            guard let item else { return }
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        await viewModel.useCoverPhoto(data)
                    }
                } catch {
                    viewModel.reportCoverProblem("Couldn't load that photo. \(error.localizedDescription)")
                }
            }
        }
    }

    @ViewBuilder
    private var coverPreview: some View {
        if let data = viewModel.coverThumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .accessibilityLabel("Your cover photo")
        } else {
            PhotoView(photo: viewModel.defaultCover, showsSymbol: false)
        }
    }

    private var companionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Companions")
            HStack(spacing: -8) {
                ForEach(viewModel.companions) { member in
                    Button {
                        if viewModel.canRemove(member) { memberToRemove = member }
                    } label: {
                        AvatarView(member: member, size: 48)
                            .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(viewModel.canRemove(member) ? "Double tap to remove" : "")
                }
                Button {
                    showAddCompanion = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 48, height: 48)
                        .background(Theme.raised, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 18)
                .accessibilityLabel("Add companion")
            }
            Text(viewModel.companions.map(\.name).joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(color)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    Text("Trips")
        .sheet(isPresented: .constant(true)) {
            TripFormView(viewModel: TripFormViewModel(store: dependencies.store, clock: dependencies.clock))
        }
        .previewEnvironment(dependencies)
}
