import MapKit
import SwiftUI

enum MapStyleChoice: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case satellite = "Satellite"

    var id: String { rawValue }

    var style: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .satellite: .hybrid(elevation: .realistic)
        }
    }
}

// MapKit map of the trip: numbered pins in plan order, the day's route,
// the geofence circles and directions to the selected stop
struct TripMapView: View {
    @State private var viewModel: TripMapViewModel
    @Environment(AppRouter.self) private var router
    @Environment(LocationService.self) private var location
    @Environment(GeofenceService.self) private var geofences
    @Environment(ReminderService.self) private var reminders
    @Environment(\.openURL) private var openURL

    @State private var position: MapCameraPosition = .automatic
    @AppStorage("mapStyle") private var mapStyle: MapStyleChoice = .standard
    // Kept with the stop it was worked out for, so a slow answer can't show on another pin
    @State private var directions: (activityID: UUID, route: MKRoute)?

    // False when the map sits next to the day plan on iPad, which has its own day tabs
    private let showsDayPicker: Bool

    init(viewModel: TripMapViewModel, showsDayPicker: Bool = true) {
        _viewModel = State(initialValue: viewModel)
        self.showsDayPicker = showsDayPicker
    }

    var body: some View {
        if let trip = viewModel.trip {
            content(trip)
        } else {
            TripMissingView()
        }
    }

    private func content(_ trip: Trip) -> some View {
        Map(position: $position, selection: $viewModel.selectedActivityID) {
            UserAnnotation()

            ForEach(geofences.fences(for: trip.id)) { fence in
                MapCircle(center: fence.coordinate, radius: fence.radius)
                    .foregroundStyle(Color.blue.opacity(0.12))
                    .stroke(Color.blue.opacity(0.5), lineWidth: 1)
            }

            if viewModel.dayRoute.count > 1 {
                MapPolyline(coordinates: viewModel.dayRoute)
                    .stroke(Color.purple.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
            }

            if let route {
                MapPolyline(route.polyline)
                    .stroke(Color.blue, lineWidth: 5)
            }

            ForEach(viewModel.pins) { pin in
                Marker(pin.activity.title, monogram: Text("\(pin.number)"), coordinate: pin.coordinate)
                    .tint(color(for: pin.activity))
                    .tag(pin.activity.id)
            }
        }
        .mapStyle(mapStyle.style)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top) {
            if showsDayPicker {
                SegmentedTabs(options: viewModel.dayTitles, selection: $viewModel.selectedDayIndex)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if let activity = viewModel.selectedActivity {
                    activityCard(activity, trip: trip)
                } else {
                    summaryCard(trip)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Map style", selection: $mapStyle) {
                        ForEach(MapStyleChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "square.3.layers.3d")
                }
                .accessibilityLabel("Map style")
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedActivityID)
        .onAppear {
            moveCamera(animated: false)
            location.requestWhenInUse()
            location.startUpdating(for: "map")
        }
        .onDisappear { location.stopUpdating(for: "map") }
        .onChange(of: viewModel.selectedDay) { moveCamera(animated: true) }
        .onChange(of: viewModel.pinned.count) { moveCamera(animated: true) }
        // Tapping a pin (or a stop in the iPad plan) brings it into view
        .onChange(of: viewModel.selectedActivityID) { _, id in
            if id != nil { focusOnSelected() }
        }
        // Only worked out again when the stop changes or the first location fix comes in
        .task(id: "\(viewModel.selectedActivityID?.uuidString ?? "")-\(location.current != nil)") {
            guard let activity = viewModel.selectedActivity else {
                directions = nil
                return
            }
            let found = await route(to: activity)
            // Another pin was picked while this one was loading
            guard !Task.isCancelled, viewModel.selectedActivityID == activity.id else { return }
            directions = found.map { (activity.id, $0) }
        }
    }

    // Directions for the selected stop only
    private var route: MKRoute? {
        guard let directions, directions.activityID == viewModel.selectedActivityID else { return nil }
        return directions.route
    }

    private func color(for activity: Activity) -> Color {
        if activity.isDone { return .green }
        if activity.id == viewModel.nextActivityID { return .blue }
        return .purple
    }

    private func activityCard(_ activity: Activity, trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(viewModel.number(of: activity))")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(color(for: activity), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.title).font(.headline)
                    Text(viewModel.subtitle(for: activity))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    withMotion { viewModel.selectedActivityID = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Theme.fill, in: Circle())
                        .tapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            if let travel = travelText(to: activity) {
                Label(travel, systemImage: route?.transportType == .automobile ? "car" : "figure.walk")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !location.isAllowed {
                Text("Allow location to see how far away it is.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    openInMaps(activity)
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
                .buttonStyle(PrimaryButtonStyle(height: 44))

                Button {
                    router.activeSheet = .newMemory(tripID: trip.id, start: .writing, activityID: activity.id)
                } label: {
                    Label("Memory", systemImage: "mic")
                }
                .buttonStyle(SecondaryButtonStyle(height: 44))

                CircleIconButton(systemImage: activity.isDone ? "checkmark.circle.fill" : "checkmark.circle", size: 44,
                                 label: activity.isDone ? "Mark as not visited" : "Mark as visited") {
                    withMotion { viewModel.toggleVisited(activity) }
                }
                .foregroundStyle(activity.isDone ? .green : .primary)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func summaryCard(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(viewModel.pinned.count) of \(viewModel.shownActivities.count) places on the map")
                .font(.headline)

            if !viewModel.unpinned.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Missing: " + viewModel.unpinned.map(\.title).joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button(viewModel.isLocating ? "Finding…" : "Find them") {
                        Task { await viewModel.locateMissing() }
                    }
                    .font(.subheadline.bold())
                    .tapTarget()
                    .disabled(viewModel.isLocating)
                }
            }
            if let message = viewModel.locateMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            arrivalAlertsRow(trip)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func arrivalAlertsRow(_ trip: Trip) -> some View {
        if location.isDenied {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Location is off for RoamPulse. Tap to turn it on in Settings.", systemImage: "location.slash")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } else if !geofences.isOn {
            HStack {
                Label("Get an alert when you reach a planned place", systemImage: "bell")
                    .font(.footnote)
                Spacer()
                Button("Turn on") { turnOnArrivalAlerts() }
                    .font(.subheadline.bold())
                    .tapTarget()
            }
        } else if !trip.remindersOn {
            Label("Reminders are off for this trip, so arrivals aren't watched.", systemImage: "bell.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            let count = geofences.fences(for: trip.id).count
            Label(count == 0 ? "Arrival alerts on. Nothing left to watch today or tomorrow."
                             : "Arrival alerts on for \(count) \(count == 1 ? "place" : "places") today and tomorrow",
                  systemImage: "bell.badge")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func turnOnArrivalAlerts() {
        reminders.settings.arrivalAlerts = true
        Task {
            await reminders.requestPermissionIfNeeded()
            location.requestAlways()
        }
    }

    private func travelText(to activity: Activity) -> String? {
        guard let distance = viewModel.distanceText(to: activity, from: location.current) else { return nil }
        guard let route else { return distance }
        let minutes = max(Int((route.expectedTravelTime / 60).rounded()), 1)
        let mode = route.transportType == .automobile ? "drive" : "walk"
        return "\(distance) • about \(ReminderPlanner.minutesText(minutes)) \(mode)"
    }

    // Walking for nearby stops, driving for further ones. Needs a connection, nil offline
    private func route(to activity: Activity) async -> MKRoute? {
        guard let destination = activity.coordinate, let current = location.current else { return nil }
        let target = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = MKMapItem(location: target, address: nil)
        request.transportType = current.distance(from: target) < 3_000 ? .walking : .automobile
        return try? await MKDirections(request: request).calculate().routes.first
    }

    private func openInMaps(_ activity: Activity) {
        guard let coordinate = activity.coordinate else { return }
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        item.name = activity.title
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    private func moveCamera(animated: Bool) {
        let target: MapCameraPosition?
        if let coordinate = viewModel.selectedActivity?.coordinate, !animated {
            target = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_500, longitudinalMeters: 1_500))
        } else {
            target = viewModel.region.map { .region($0) }
        }
        guard let target else { return }
        if animated {
            withMotion { position = target }
        } else {
            position = target
        }
    }

    private func focusOnSelected() {
        guard let coordinate = viewModel.selectedActivity?.coordinate else { return }
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_500, longitudinalMeters: 1_500)
        withMotion { position = .region(region) }
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        TripMapView(viewModel: TripMapViewModel(tripID: dependencies.previewTripID, store: dependencies.store,
                                                clock: dependencies.clock, places: dependencies.places))
    }
    .previewEnvironment(dependencies)
}
