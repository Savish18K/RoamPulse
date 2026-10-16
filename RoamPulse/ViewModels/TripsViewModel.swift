import Foundation
import Observation

// MARK: - TripsListViewModel

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

// MARK: - TripFormViewModel

/// Create Trip and Edit Trip sheet.
@MainActor
@Observable
final class TripFormViewModel {
    private let store: TripStore
    /// The trip being edited, or nil when creating a new one.
    let tripID: UUID?

    var name = ""
    var destination = ""
    var startDate: Date
    var endDate: Date
    var budgetText = ""
    var remindersOn = true
    var newCompanionName = ""
    private(set) var companions: [Member]

    let destinationSuggestions = ["Galle Fort", "Unawatuna", "Hikkaduwa", "Mirissa"]

    init(tripID: UUID? = nil, store: TripStore, clock: Clock) {
        self.store = store
        self.tripID = tripID

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
        }
    }

    private var existingTrip: Trip? { tripID.flatMap(store.trip) }

    var isEditing: Bool { tripID != nil }
    var title: String { isEditing ? "Edit Trip" : "Create Trip" }
    var saveTitle: String { isEditing ? "Save Changes" : "Save Trip" }

    // MARK: Validation

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

    // MARK: Companions

    func addCompanion() {
        let newName = newCompanionName.trimmed
        newCompanionName = ""
        guard !newName.isEmpty,
              !companions.contains(where: { $0.name.caseInsensitiveCompare(newName) == .orderedSame }) else { return }
        let color = Member.palette[companions.count % Member.palette.count]
        companions.append(Member(name: newName, colorHex: color))
    }

    /// You can't remove yourself, or someone who is already part of an expense.
    func canRemove(_ member: Member) -> Bool {
        if member.isMe { return false }
        return !(existingTrip?.hasMoney(involving: member) ?? false)
    }

    func remove(_ member: Member) {
        guard canRemove(member) else { return }
        companions.removeAll { $0.id == member.id }
    }

    // MARK: Saving

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
                packing: PackingAdvisor.defaultTemplate()
            )
            return store.addTrip(trip)
        }

        let newDayCount = dayCount
        return store.updateTrip(tripID) { trip in
            trip.name = name.trimmed
            trip.destination = destination.trimmed
            trip.startDate = startDate
            trip.endDate = endDate
            trip.budget = budget
            trip.remindersOn = remindersOn
            trip.members = companions
            trip.activities = ItineraryPlanner.clamp(trip.activities, toDayCount: newDayCount)
        }
    }
}

extension String {
    /// The string without spaces or new lines at either end.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
