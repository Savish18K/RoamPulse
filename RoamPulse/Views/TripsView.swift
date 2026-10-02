import SwiftUI

// MARK: - TripsListView

struct TripsListView: View {
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var searchText = ""
    @State private var tripToDelete: Trip?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let active = store.activeTrip, matches(active) {
                    sectionTitle("Active Trip")
                    NavigationLink(value: AppRoute.tripDetail(active.id)) {
                        ActiveTripCard(trip: active, weather: store.weather)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { deleteButton(active) }
                }

                let upcoming = store.upcomingTrips.filter(matches)
                if !upcoming.isEmpty {
                    sectionTitle("Upcoming")
                    tripGroup(upcoming) { "\($0.compactDateRange) • \($0.daysUntilStart()) days left" }
                }

                let completed = store.completedTrips.filter(matches)
                if !completed.isEmpty {
                    sectionTitle("Completed")
                    tripGroup(completed) { "\($0.compactDateRange) • \($0.totalSpent.lkr)" }
                }

                if store.trips.isEmpty {
                    ContentUnavailableView("No trips yet", systemImage: "suitcase",
                                           description: Text("Tap Create Trip to plan your first trip."))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Trips")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search trips, places or memories...")
        .safeAreaInset(edge: .bottom) {
            FloatingActionBar(primaryTitle: "Create Trip", primaryAction: { router.activeSheet = .createTrip })
        }
        .confirmationDialog(
            "Delete this trip?",
            isPresented: Binding(get: { tripToDelete != nil }, set: { if !$0 { tripToDelete = nil } }),
            titleVisibility: .visible,
            presenting: tripToDelete
        ) { trip in
            Button("Delete \(trip.name)", role: .destructive) {
                withAnimation { store.deleteTrip(trip.id) }
            }
        } message: { _ in
            Text("Its itinerary, packing list, expenses and memories will be removed from this iPhone.")
        }
    }

    private func matches(_ trip: Trip) -> Bool {
        searchText.isEmpty
            || trip.name.localizedCaseInsensitiveContains(searchText)
            || trip.destination.localizedCaseInsensitiveContains(searchText)
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
                        PhotoView(photo: trip.cover)
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
                .contextMenu { deleteButton(trip) }

                if trip.id != trips.last?.id {
                    Divider().padding(.leading, 84)
                }
            }
        }
        .card(padding: 0)
    }

    private func deleteButton(_ trip: Trip) -> some View {
        Button(role: .destructive) {
            tripToDelete = trip
        } label: {
            Label("Delete Trip", systemImage: "trash")
        }
    }
}

/// Big photo card for the trip that is happening now.
struct ActiveTripCard: View {
    let trip: Trip
    let weather: WeatherSnapshot

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                PhotoView(photo: trip.cover, showsSymbol: false)
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
                    GlassPill(trip.statusText)
                    Spacer()
                    GlassPill("\(weather.temperature)° • \(weather.location)")
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
    NavigationStack { TripsListView() }
        .environment(TripStore())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}

// MARK: - CreateTripView

struct CreateTripView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var destination = ""
    @State private var startDate = DemoClock.date(2027, 1, 9)
    @State private var endDate = DemoClock.date(2027, 1, 11)
    @State private var budget = ""
    @State private var companions = SampleData.crew
    @State private var remindersOn = true
    @State private var showDatePickers = false
    @State private var showAddCompanion = false
    @State private var newCompanionName = ""

    private let suggestions = ["Galle Fort", "Unawatuna", "Hikkaduwa", "Mirissa"]
    private let companionColors: [Color] = [.teal, .orange, .pink, .indigo, .mint]

    private var datesAreValid: Bool { DemoClock.days(from: startDate, to: endDate) >= 0 }
    private var dayCount: Int { DemoClock.days(from: startDate, to: endDate) + 1 }
    private var canSave: Bool {
        datesAreValid
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !destination.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    FormField(label: "Trip Name") {
                        TextField("Southern Coast Weekend", text: $name)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        FormField(label: "Destination") {
                            TextField("Galle", text: $destination)
                        }
                        FlowLayout {
                            ForEach(suggestions, id: \.self) { place in
                                Button { destination = place } label: {
                                    Chip(place, isSelected: destination == place)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Dates")
                            Button {
                                withAnimation { showDatePickers.toggle() }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dateRangeText).font(.headline).foregroundStyle(.primary)
                                    Text(datesAreValid ? "\(dayCount) days calculated" : "Check the dates")
                                        .font(.caption)
                                        .foregroundStyle(datesAreValid ? .green : .red)
                                }
                                .fieldStyle()
                            }
                            .buttonStyle(.plain)
                        }
                        FormField(label: "Budget") {
                            HStack(spacing: 6) {
                                Text("LKR").foregroundStyle(.secondary)
                                TextField("90,000", text: $budget)
                                    .keyboardType(.numberPad)
                                    .font(.headline)
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    if showDatePickers {
                        VStack(spacing: 4) {
                            DatePicker("Start", selection: $startDate, displayedComponents: .date)
                            DatePicker("End", selection: $endDate, displayedComponents: .date)
                        }
                        .fieldStyle()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Companions")
                        HStack(spacing: -8) {
                            ForEach(companions) { member in
                                AvatarView(member: member, size: 48)
                                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
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
                    }

                    Toggle(isOn: $remindersOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bedtime & packing reminders").font(.headline)
                            Text("Auto-ping scheduled tasks").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)

                    if !datesAreValid {
                        Text("The end date must be on or after the start date.")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Save Trip", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSave)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .navigationTitle("Create Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Add companion", isPresented: $showAddCompanion) {
                TextField("Name", text: $newCompanionName)
                Button("Add") { addCompanion() }
                Button("Cancel", role: .cancel) { newCompanionName = "" }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    private var dateRangeText: String {
        let sameMonth = startDate.text("MMM yyyy") == endDate.text("MMM yyyy")
        return startDate.text(sameMonth ? "d" : "d MMM") + " – " + endDate.text("d MMM yyyy")
    }

    private func addCompanion() {
        let trimmed = newCompanionName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let color = companionColors[companions.count % companionColors.count]
        companions.append(Member(name: trimmed, color: color))
        newCompanionName = ""
    }

    private func save() {
        let trip = Trip(
            name: name.trimmingCharacters(in: .whitespaces),
            destination: destination.trimmingCharacters(in: .whitespaces),
            startDate: startDate,
            endDate: endDate,
            budget: Double(budget.filter(\.isNumber)) ?? 0,
            members: companions,
            cover: .coconutTreeHill,
            remindersOn: remindersOn,
            packing: SampleData.packingTemplate(packed: false)
        )
        store.addTrip(trip)
        dismiss()
    }
}

#Preview {
    Text("Trips")
        .sheet(isPresented: .constant(true)) {
            CreateTripView().environment(TripStore())
        }
        .preferredColorScheme(.dark)
}
