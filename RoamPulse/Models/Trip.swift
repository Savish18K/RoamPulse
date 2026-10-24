import SwiftUI

// Plain structs used by the views, CoreDataTripRepository converts them to entities

struct Member: Identifiable, Hashable {
    var id: UUID
    var name: String
    var initials: String
    // Stored as 0xRRGGBB so it fits in Core Data
    var colorHex: Int
    var isMe: Bool
    // Set once they join, used to work out isMe on each phone
    var userUID: String?

    // Defaults to the first two letters
    init(id: UUID = UUID(), name: String, initials: String? = nil, colorHex: Int, isMe: Bool = false,
         userUID: String? = nil) {
        self.id = id
        self.name = name
        self.initials = initials ?? String(name.prefix(2)).uppercased()
        self.colorHex = colorHex
        self.isMe = isMe
        self.userUID = userUID
    }

    var color: Color { Color(hex: UInt32(colorHex)) }

    // Colours given to new companions in order
    static let palette = [0x4FB3A9, 0xE39B4B, 0x6F7BD9, 0xC9658A, 0x6E9F7A, 0x5B8FD6]
}

struct UserProfile: Equatable {
    var fullName: String
    var email: String
}

enum TripStatus {
    case upcoming, active, completed
}

struct Trip: Identifiable, Hashable {
    var id = UUID()
    var name: String
    // e.g. "Kandy to Ella"
    var destination: String
    var startDate: Date
    var endDate: Date
    var budget: Double
    var members: [Member]
    var cover: SamplePhoto
    var remindersOn = true
    var activities: [Activity] = []
    var packing: [PackingItem] = []
    var expenses: [Expense] = []
    var payments: [Payment] = []
    // Picked cover photo, local only. nil uses the sample cover
    var coverImageID: UUID?
    // Only the owner can delete it for everyone
    var ownerUID: String?
    // Includes the owner, checked by the Firestore rules
    var memberUIDs: [String] = []
    // Set from the place search, or looked up the first time weather loads
    var latitude: Double?
    var longitude: Double?
}

extension Trip {
    var isShared: Bool { memberUIDs.count > 1 }

    var hasCoordinates: Bool { latitude != nil && longitude != nil }

    var dayCount: Int { max(Calendar.trip.days(from: startDate, to: endDate) + 1, 1) }

    func status(at now: Date) -> TripStatus {
        let calendar = Calendar.trip
        if calendar.days(from: now, to: startDate) > 0 { return .upcoming }
        if calendar.days(from: endDate, to: now) > 0 { return .completed }
        return .active
    }

    // Starts at 1, nil if the trip isn't active
    func dayNumber(at now: Date) -> Int? {
        guard status(at: now) == .active else { return nil }
        return Calendar.trip.days(from: startDate, to: now) + 1
    }

    func daysUntilStart(from now: Date) -> Int {
        Calendar.trip.days(from: now, to: startDate)
    }

    func date(ofDay day: Int) -> Date {
        Calendar.trip.date(byAdding: .day, value: day - 1, to: startDate) ?? startDate
    }

    var routeText: String { destination.replacingOccurrences(of: " to ", with: " → ") }

    // e.g. "Kandy to Ella" -> "Ella"
    var mainPlace: String {
        destination.components(separatedBy: " to ").last?.trimmingCharacters(in: .whitespaces) ?? destination
    }

    var dateRangeText: String {
        let sameMonth = startDate.text("MMM") == endDate.text("MMM")
        return startDate.text(sameMonth ? "EEE d" : "EEE d MMM") + " to " + endDate.text("EEE d MMM")
    }

    var compactDateRange: String {
        let sameMonth = startDate.text("MMM yyyy") == endDate.text("MMM yyyy")
        return startDate.text(sameMonth ? "d" : "d MMM") + "–" + endDate.text("d MMM yyyy")
    }

    func statusText(at now: Date) -> String {
        switch status(at: now) {
        case .active: "Active • Day \(dayNumber(at: now) ?? 1) of \(dayCount)"
        case .upcoming:
            daysUntilStart(from: now) == 1 ? "Tomorrow" : "In \(daysUntilStart(from: now)) days"
        case .completed: "Completed"
        }
    }
}

struct TripSections {
    var active: [Trip] = []
    var upcoming: [Trip] = []
    var completed: [Trip] = []
}

extension Sequence where Element == Trip {
    func sections(at now: Date) -> TripSections {
        var sections = TripSections()
        for trip in self {
            switch trip.status(at: now) {
            case .active: sections.active.append(trip)
            case .upcoming: sections.upcoming.append(trip)
            case .completed: sections.completed.append(trip)
            }
        }
        sections.active.sort { $0.startDate < $1.startDate }
        sections.upcoming.sort { $0.startDate < $1.startDate }
        sections.completed.sort { $0.endDate > $1.endDate }
        return sections
    }
}

extension Trip {
    func activities(onDay day: Int) -> [Activity] {
        ItineraryPlanner.ordered(activities.filter { $0.day == day })
    }

    func nextActivity(at now: Date) -> Activity? {
        guard let today = dayNumber(at: now) else { return nil }
        let minutesNow = Calendar.trip.minutesSinceMidnight(now)
        return activities(onDay: today).first { !$0.isDone && $0.minutes >= minutesNow }
    }

    func intensity(ofDay day: Int) -> DayIntensity? {
        ItineraryPlanner.intensity(of: activities(onDay: day))
    }
}

extension Trip {
    var packedCount: Int { packing.filter(\.isPacked).count }

    var packingProgress: Double { packing.isEmpty ? 0 : Double(packedCount) / Double(packing.count) }

    // Payments aren't spending so they're not counted
    var totalSpent: Double { expenses.reduce(0) { $0 + $1.amount } }

    var budgetLeft: Double { budget - totalSpent }

    // Capped at 1 for the progress bar
    var spentFraction: Double { budget > 0 ? min(totalSpent / budget, 1) : 0 }

    var budgetStatus: BudgetStatus { ExpenseCalculator.budgetStatus(spent: totalSpent, budget: budget) }

    func spent(on category: ExpenseCategory) -> Double {
        expenses.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
    }

    func member(_ id: UUID) -> Member? { members.first { $0.id == id } }

    // Can't remove a member that has money attached
    func hasMoney(involving member: Member) -> Bool {
        expenses.contains { $0.paidBy.id == member.id || $0.shares.contains { $0.member.id == member.id } }
            || payments.contains { $0.from.id == member.id || $0.to.id == member.id }
    }
}

enum Effort: String, CaseIterable, Identifiable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"

    var id: Self { self }
}

struct Activity: Identifiable, Hashable {
    var id = UUID()
    var day: Int
    var title: String
    // e.g. 17:30 -> 1050
    var minutes: Int
    var place: String
    var effort: Effort
    var isOutdoor = false
    var isDone = false

    var timeText: String { minutes.clockText }
}

enum DayIntensity {
    case easy, moderate, demanding

    var title: String {
        switch self {
        case .easy: "Easy day"
        case .moderate: "Moderate physical day"
        case .demanding: "Demanding day"
        }
    }

    var color: Color {
        switch self {
        case .easy: .green
        case .moderate: .orange
        case .demanding: .red
        }
    }

    var icon: String {
        switch self {
        case .easy: "figure.walk"
        case .moderate: "figure.hiking"
        case .demanding: "flame.fill"
        }
    }
}

struct PackingItem: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var category: String
    var isPacked = false
}

enum ExpenseCategory: String, CaseIterable, Identifiable {
    case transport = "Transport"
    case lodging = "Lodging"
    case food = "Food"
    case activities = "Activities"

    var id: Self { self }

    var color: Color {
        switch self {
        case .transport: .blue
        case .lodging: .indigo
        case .food: .orange
        case .activities: .green
        }
    }

    var icon: String {
        switch self {
        case .transport: "car.fill"
        case .lodging: "bed.double.fill"
        case .food: "fork.knife"
        case .activities: "ticket.fill"
        }
    }
}

enum SplitMethod: String, CaseIterable, Identifiable {
    case equal = "Equal"
    case custom = "Custom"

    var id: Self { self }
}

struct ExpenseShare: Hashable {
    var member: Member
    var amount: Double
}

struct Expense: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var amount: Double
    var category: ExpenseCategory
    var paidBy: Member
    var splitMethod: SplitMethod = .equal
    // Always adds up to amount
    var shares: [ExpenseShare]
    var date: Date

    var participants: [Member] { shares.map(\.member) }

    func share(of member: Member) -> Double {
        shares.first { $0.member.id == member.id }?.amount ?? 0
    }
}

struct Payment: Identifiable, Hashable {
    var id = UUID()
    var from: Member
    var to: Member
    var amount: Double
    var date: Date
}

// Positive means they get money back
struct Balance: Identifiable, Hashable {
    var member: Member
    var amount: Double

    var id: UUID { member.id }

    var text: String {
        if abs(amount) < 0.01 { return "\(member.name) is settled up" }
        return amount > 0 ? "\(member.name) gets back \(amount.lkr)" : "\(member.name) owes \((-amount).lkr)"
    }
}

// Calculated, not saved
struct Settlement: Identifiable, Hashable {
    var from: Member
    var to: Member
    var amount: Double

    var id: String { "\(from.id)-\(to.id)" }
}

enum BudgetStatus: Equatable {
    case noBudget
    case onTrack
    // 90% or more used
    case nearLimit
    case overBudget

    var message: String? {
        switch self {
        case .noBudget, .onTrack: nil
        case .nearLimit: "You have used 90% of the budget."
        case .overBudget: "You are over budget."
        }
    }

    var color: Color {
        switch self {
        case .noBudget, .onTrack: .primary
        case .nearLimit: .orange
        case .overBudget: .red
        }
    }
}

// Has to be in the same file for the synthesised conformance
extension Member: Encodable {}
extension Trip: Encodable {}
extension Activity: Encodable {}
extension Effort: Encodable {}
extension PackingItem: Encodable {}
extension ExpenseCategory: Encodable {}
extension SplitMethod: Encodable {}
extension ExpenseShare: Encodable {}
extension Expense: Encodable {}
extension Payment: Encodable {}
