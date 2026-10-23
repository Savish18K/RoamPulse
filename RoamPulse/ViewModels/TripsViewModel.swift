import Foundation
import Observation

/// Trips tab: trips grouped into Active, Upcoming and Completed, with search and delete.
@MainActor
@Observable
final class TripsListViewModel {
    private let store: TripStore
    private let clock: Clock
    private let weatherService: WeatherService

    var searchText = ""
    /// The trip waiting for the user to confirm the delete.
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

    /// Matches the trip name, destination, activities and the titles of its memories.
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

/// Create Trip and Edit Trip sheet.
@MainActor
@Observable
final class TripFormViewModel {
    private let store: TripStore
    /// The trip being edited, or nil when creating a new one.
    let tripID: UUID?

    var name = ""
    /// Typing a different destination forgets the place picked from the suggestions (and its coordinates).
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

    /// What happens to the cover photo when the form is saved.
    enum CoverChange: Equatable {
        case unchanged
        case replace(PreparedImage)
        case remove
    }

    private(set) var coverChange: CoverChange = .unchanged
    /// True while a picked photo is being resized.
    private(set) var isPreparingCover = false
    /// Set when a picked file couldn't be read as a photo.
    private(set) var coverProblem: String?

    /// Shown when there are no search results (e.g. offline).
    let destinationSuggestions = ["Galle Fort", "Unawatuna", "Hikkaduwa", "Mirissa"]
    /// Places matching the destination, from OpenWeatherMap's geocoding.
    private(set) var placeSuggestions: [Place] = []
    /// The suggestion the user tapped. Its coordinates are saved with the trip for the weather.
    private(set) var pickedPlace: Place?
    private let weather: WeatherService?
    /// The destination when the form opened, so editing a trip doesn't search until it changes.
    private var originalDestination = ""

    init(tripID: UUID? = nil, store: TripStore, clock: Clock, weather: WeatherService? = nil) {
        self.store = store
        self.tripID = tripID
        self.weather = weather

        // A new trip starts a week from today and lasts three days.
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

    /// Looks up places matching the destination. Called by the view a moment after typing stops.
    func searchPlaces() async {
        let query = destination.trimmed
        guard let weather, query.count >= 2, pickedPlace == nil, query != originalDestination else {
            placeSuggestions = []
            return
        }
        // Offline or no results: the fixed suggestions are shown instead.
        placeSuggestions = (try? await weather.searchPlaces(query)) ?? []
    }

    func pick(_ place: Place) {
        pickedPlace = place
        destination = place.name
        placeSuggestions = []
    }

    /// The trip's own photo will be shown (a new one was picked, or it already had one that isn't being removed).
    var hasCustomCover: Bool {
        switch coverChange {
        case .replace: true
        case .remove: false
        case .unchanged: existingTrip?.coverImageID != nil
        }
    }

    /// The small JPEG for the form's preview: the newly picked photo or the saved one.
    var coverThumbnailData: Data? {
        switch coverChange {
        case .replace(let image): image.thumbnail
        case .remove: nil
        case .unchanged: existingTrip?.coverImageID.flatMap { store.imageData($0, thumbnail: true) }
        }
    }

    /// The sample photo used when there is no photo of the user's own.
    var defaultCover: SamplePhoto {
        existingTrip?.cover ?? .cover(for: destination)
    }

    /// Resizes a photo from the photo picker. Nothing is saved until the form is saved.
    func useCoverPhoto(_ data: Data) async {
        isPreparingCover = true
        coverProblem = nil
        // Resizing a 12 MP photo takes a moment, so it runs off the main thread.
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

    /// Digits only, so "90,000" and "90000" both work.
    var budget: Double { Double(budgetText.filter(\.isNumber)) ?? 0 }

    var canSave: Bool {
        datesAreValid && !name.trimmed.isEmpty && !destination.trimmed.isEmpty
    }

    /// "9 – 11 Jan 2027"
    var dateRangeText: String {
        let sameMonth = startDate.text("MMM yyyy") == endDate.text("MMM yyyy")
        return startDate.text(sameMonth ? "d" : "d MMM") + " – " + endDate.text("d MMM yyyy")
    }

    /// When editing makes the trip shorter, activities on the removed days move to the new last day.
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

    /// You can't remove yourself, someone who has joined with their own account (they leave the trip
    /// themselves), or someone who is already part of an expense.
    func canRemove(_ member: Member) -> Bool {
        if member.isMe || member.userUID != nil { return false }
        return !(existingTrip?.hasMoney(involving: member) ?? false)
    }

    func remove(_ member: Member) {
        guard canRemove(member) else { return }
        companions.removeAll { $0.id == member.id }
    }

    /// Creates or updates the trip. Returns false if the form isn't valid or saving failed.
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
                // A new destination: use the picked place, or look it up again when the weather loads.
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

    /// The photo is saved after the trip, because it is linked to the trip's saved row.
    private func saveCoverChange(for tripID: UUID) -> Bool {
        switch coverChange {
        case .unchanged: true
        case .replace(let image): store.setCoverPhoto(image, for: tripID)
        case .remove: store.setCoverPhoto(nil, for: tripID)
        }
    }
}

extension String {
    /// The string without spaces or new lines at either end.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
