import Foundation
import Observation

@MainActor
@Observable
final class TripsListViewModel {
    private let store: TripStore
    private let clock: Clock
    private let weatherService: WeatherService

    var searchText = ""
    var tripPendingDelete: Trip?
    private(set) var weather: WeatherSnapshot?

    init(store: TripStore, clock: Clock, weather: WeatherService) {
        self.store = store
        self.clock = clock
        self.weatherService = weather
    }

    var now: Date { clock.now }

    private var sections: TripSections {
        store.trips.filter(matchesSearch).sections(at: now)
    }

    var activeTrips: [Trip] { sections.active }
    var upcomingTrips: [Trip] { sections.upcoming }
    var completedTrips: [Trip] { sections.completed }

    var hasNoTrips: Bool { store.trips.isEmpty }

    var hasNoSearchResults: Bool {
        !hasNoTrips && activeTrips.isEmpty && upcomingTrips.isEmpty && completedTrips.isEmpty
    }

    // Name, destination, activities and memory titles
    func matchesSearch(_ trip: Trip) -> Bool {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        let words = [trip.name, trip.destination]
            + trip.activities.flatMap { [$0.title, $0.place] }
            + store.memories(inTrip: trip.id).map(\.title)
        return words.contains { $0.localizedCaseInsensitiveContains(text) }
    }

    func statusText(for trip: Trip) -> String { trip.statusText(at: now) }

    func upcomingSubtitle(for trip: Trip) -> String {
        let days = trip.daysUntilStart(from: now)
        return "\(trip.compactDateRange) • " + (days == 1 ? "starts tomorrow" : "\(days) days left")
    }

    func completedSubtitle(for trip: Trip) -> String {
        "\(trip.compactDateRange) • \(trip.totalSpent.lkr)"
    }

    func requestDelete(_ trip: Trip) {
        tripPendingDelete = trip
    }

    func confirmDelete() {
        guard let trip = tripPendingDelete else { return }
        store.deleteTrip(trip.id)
        tripPendingDelete = nil
    }

    func loadWeather() async {
        guard let trip = activeTrips.first else {
            weather = nil
            return
        }
        weather = try? await weatherService.forecast(for: trip)
    }
}

// Create / edit trip sheet
@MainActor
@Observable
final class TripFormViewModel {
    private let store: TripStore
    // nil when creating
    let tripID: UUID?

    var name = ""
    // Typing again clears the picked place and its coordinates
    var destination = "" {
        didSet {
            if destination != pickedPlace?.name {
                pickedPlace = nil
            }
        }
    }
    var startDate: Date
    var endDate: Date
    var budgetText = ""
    var remindersOn = true
    var newCompanionName = ""
    private(set) var companions: [Member]

    enum CoverChange: Equatable {
        case unchanged
        case replace(PreparedImage)
        case remove
    }

    private(set) var coverChange: CoverChange = .unchanged
    private(set) var isPreparingCover = false
    private(set) var coverProblem: String?

    // Used when the search gives nothing (e.g. offline)
    let destinationSuggestions = ["Galle Fort", "Unawatuna", "Hikkaduwa", "Mirissa"]
    // From OpenWeatherMap geocoding
    private(set) var placeSuggestions: [Place] = []
    // Coordinates are saved with the trip
    private(set) var pickedPlace: Place?
    private let weather: WeatherService?
    // So editing doesn't search until the destination changes
    private var originalDestination = ""

    init(tripID: UUID? = nil, store: TripStore, clock: Clock, weather: WeatherService? = nil) {
        self.store = store
        self.tripID = tripID
        self.weather = weather

        // New trips start next week and last 3 days
        let calendar = Calendar.trip
        let today = calendar.startOfDay(for: clock.now)
        startDate = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        endDate = calendar.date(byAdding: .day, value: 9, to: today) ?? today
        let me = store.me
        companions = [Member(name: me.name, initials: me.initials, colorHex: me.colorHex, isMe: true)]

        if let tripID, let trip = store.trip(tripID) {
            name = trip.name
            destination = trip.destination
            startDate = trip.startDate
            endDate = trip.endDate
            budgetText = trip.budget > 0 ? String(Int(trip.budget)) : ""
            remindersOn = trip.remindersOn
            companions = trip.members
            originalDestination = trip.destination
        }
    }

    // The view calls this after a short delay
    func searchPlaces() async {
        let query = destination.trimmed
        guard let weather, query.count >= 2, pickedPlace == nil, query != originalDestination else {
            placeSuggestions = []
            return
        }
        // Fall back to the fixed suggestions
        placeSuggestions = (try? await weather.searchPlaces(query)) ?? []
    }

    func pick(_ place: Place) {
        pickedPlace = place
        destination = place.name
        placeSuggestions = []
    }

    var hasCustomCover: Bool {
        switch coverChange {
        case .replace: true
        case .remove: false
        case .unchanged: existingTrip?.coverImageID != nil
        }
    }

    var coverThumbnailData: Data? {
        switch coverChange {
        case .replace(let image): image.thumbnail
        case .remove: nil
        case .unchanged: existingTrip?.coverImageID.flatMap { store.imageData($0, thumbnail: true) }
        }
    }

    var defaultCover: SamplePhoto {
        existingTrip?.cover ?? .cover(for: destination)
    }

    // Not saved until the form is saved
    func useCoverPhoto(_ data: Data) async {
        isPreparingCover = true
        coverProblem = nil
        // Slow for big photos so do it off the main thread
        let prepared = await Task.detached(priority: .userInitiated) { ImageProcessor.prepare(data) }.value
        isPreparingCover = false
        if let prepared {
            coverChange = .replace(prepared)
        } else {
            coverProblem = "That file couldn't be opened as a photo."
        }
    }

    func reportCoverProblem(_ message: String) {
        coverProblem = message
    }

    func removeCoverPhoto() {
        coverChange = existingTrip?.coverImageID == nil ? .unchanged : .remove
        coverProblem = nil
    }

    private var existingTrip: Trip? { tripID.flatMap(store.trip) }

    var isEditing: Bool { tripID != nil }
    var title: String { isEditing ? "Edit Trip" : "Create Trip" }
    var saveTitle: String { isEditing ? "Save Changes" : "Save Trip" }

    var datesAreValid: Bool { Calendar.trip.days(from: startDate, to: endDate) >= 0 }

    var dayCount: Int { Calendar.trip.days(from: startDate, to: endDate) + 1 }

    // Digits only so "90,000" works too
    var budget: Double { Double(budgetText.filter(\.isNumber)) ?? 0 }

    var canSave: Bool {
        datesAreValid && !name.trimmed.isEmpty && !destination.trimmed.isEmpty
    }

    var dateRangeText: String {
        let sameMonth = startDate.text("MMM yyyy") == endDate.text("MMM yyyy")
        return startDate.text(sameMonth ? "d" : "d MMM") + " – " + endDate.text("d MMM yyyy")
    }

    // Activities on removed days move to the new last day
    var shortenedTripWarning: String? {
        guard let trip = existingTrip, datesAreValid else { return nil }
        let count = trip.activities.filter { $0.day > dayCount }.count
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? "activity" : "activities") on removed days will move to Day \(dayCount)."
    }

    func addCompanion() {
        let newName = newCompanionName.trimmed
        newCompanionName = ""
        guard !newName.isEmpty,
              !companions.contains(where: { $0.name.caseInsensitiveCompare(newName) == .orderedSame }) else { return }
        let color = Member.palette[companions.count % Member.palette.count]
        companions.append(Member(name: newName, colorHex: color))
    }

    // Can't remove yourself, someone with an account, or someone in an expense
    func canRemove(_ member: Member) -> Bool {
        if member.isMe || member.userUID != nil { return false }
        return !(existingTrip?.hasMoney(involving: member) ?? false)
    }

    func remove(_ member: Member) {
        guard canRemove(member) else { return }
        companions.removeAll { $0.id == member.id }
    }

    // false if invalid or the save failed
    func save() -> Bool {
        guard canSave else { return false }

        guard let tripID else {
            let trip = Trip(
                name: name.trimmed,
                destination: destination.trimmed,
                startDate: startDate,
                endDate: endDate,
                budget: budget,
                members: companions,
                cover: .cover(for: destination),
                remindersOn: remindersOn,
                packing: PackingAdvisor.defaultTemplate(),
                latitude: pickedPlace?.latitude,
                longitude: pickedPlace?.longitude
            )
            guard store.addTrip(trip) else { return false }
            return saveCoverChange(for: trip.id)
        }

        let newDayCount = dayCount
        let picked = pickedPlace
        let saved = store.updateTrip(tripID) { trip in
            if trip.destination != destination.trimmed || picked != nil {
                // Use the picked place, otherwise it's looked up when the weather loads
                trip.latitude = picked?.latitude
                trip.longitude = picked?.longitude
            }
            trip.name = name.trimmed
            trip.destination = destination.trimmed
            trip.startDate = startDate
            trip.endDate = endDate
            trip.budget = budget
            trip.remindersOn = remindersOn
            trip.members = companions
            trip.activities = ItineraryPlanner.clamp(trip.activities, toDayCount: newDayCount)
        }
        return saved && saveCoverChange(for: tripID)
    }

    // Saved after the trip since it links to the trip row
    private func saveCoverChange(for tripID: UUID) -> Bool {
        switch coverChange {
        case .unchanged: true
        case .replace(let image): store.setCoverPhoto(image, for: tripID)
        case .remove: store.setCoverPhoto(nil, for: tripID)
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
