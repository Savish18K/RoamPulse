import SwiftUI

// These are plain value types. Views and view models only ever see these;
// Core Data entities are converted to and from them in CoreDataTripRepository.

// MARK: - Member

/// A person travelling on a trip.
struct Member: Identifiable, Hashable {
    var id: UUID
    var name: String
    var initials: String
    /// Avatar colour as 0xRRGGBB, so it can be saved in Core Data.
    var colorHex: Int
    var isMe: Bool

    /// `initials` defaults to the first two letters, e.g. "Nimal" → "NI".
    init(id: UUID = UUID(), name: String, initials: String? = nil, colorHex: Int, isMe: Bool = false) {
        self.id = id
        self.name = name
        self.initials = initials ?? String(name.prefix(2)).uppercased()
        self.colorHex = colorHex
        self.isMe = isMe
    }

    var color: Color { Color(hex: UInt32(colorHex)) }

    /// Colours handed out to new companions in turn.
    static let palette = [0x4FB3A9, 0xE39B4B, 0x6F7BD9, 0xC9658A, 0x6E9F7A, 0x5B8FD6]
}

/// The local (account-free) user shown on the Profile screen.
struct UserProfile {
    var fullName: String
    var email: String
}

// MARK: - Trip

enum TripStatus {
    case upcoming, active, completed
}

/// A trip is the container for its itinerary, packing list and expenses.
struct Trip: Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Route or place, e.g. "Kandy to Ella".
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
    /// Settle-up payments the group has already made.
    var payments: [Payment] = []
}

// MARK: - Dates & status

extension Trip {
    var dayCount: Int { max(Calendar.trip.days(from: startDate, to: endDate) + 1, 1) }

    func status(at now: Date) -> TripStatus {
        let calendar = Calendar.trip
        if calendar.days(from: now, to: startDate) > 0 { return .upcoming }
        if calendar.days(from: endDate, to: now) > 0 { return .completed }
        return .active
    }

    /// 1-based day number while the trip is active, otherwise nil.
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

    /// "Kandy → Ella"
    var routeText: String { destination.replacingOccurrences(of: " to ", with: " → ") }

    /// Last place on the route, used for the weather, e.g. "Kandy to Ella" → "Ella".
    var mainPlace: String {
        destination.components(separatedBy: " to ").last?.trimmingCharacters(in: .whitespaces) ?? destination
    }

    /// "Sat 12 to Tue 15 Dec"
    var dateRangeText: String {
        let sameMonth = startDate.text("MMM") == endDate.text("MMM")
        return startDate.text(sameMonth ? "EEE d" : "EEE d MMM") + " to " + endDate.text("EEE d MMM")
    }

    /// "10–14 Apr 2027"
    var compactDateRange: String {
        let sameMonth = startDate.text("MMM yyyy") == endDate.text("MMM yyyy")
        return startDate.text(sameMonth ? "d" : "d MMM") + "–" + endDate.text("d MMM yyyy")
    }

    /// "Active • Day 2 of 4", "In 12 days" or "Completed".
    func statusText(at now: Date) -> String {
        switch status(at: now) {
        case .active: "Active • Day \(dayNumber(at: now) ?? 1) of \(dayCount)"
        case .upcoming:
            daysUntilStart(from: now) == 1 ? "Tomorrow" : "In \(daysUntilStart(from: now)) days"
        case .completed: "Completed"
        }
    }
}

/// Trips split into the three groups shown on the Trips tab.
struct TripSections {
    /// Happening now, earliest start first.
    var active: [Trip] = []
    /// Soonest first.
    var upcoming: [Trip] = []
    /// Most recently finished first.
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

// MARK: - Itinerary

extension Trip {
    /// The day's activities in time order (see `ItineraryPlanner`).
    func activities(onDay day: Int) -> [Activity] {
        ItineraryPlanner.ordered(activities.filter { $0.day == day })
    }

    /// The next activity today that hasn't happened yet.
    func nextActivity(at now: Date) -> Activity? {
        guard let today = dayNumber(at: now) else { return nil }
        let minutesNow = Calendar.trip.minutesSinceMidnight(now)
        return activities(onDay: today).first { !$0.isDone && $0.minutes >= minutesNow }
    }

    func intensity(ofDay day: Int) -> DayIntensity? {
        ItineraryPlanner.intensity(of: activities(onDay: day))
    }
}

// MARK: - Packing & money

extension Trip {
    var packedCount: Int { packing.filter(\.isPacked).count }

    var packingProgress: Double { packing.isEmpty ? 0 : Double(packedCount) / Double(packing.count) }

    /// Money spent on the trip. Settle-up payments are not spending, so they are not counted.
    var totalSpent: Double { expenses.reduce(0) { $0 + $1.amount } }

    var budgetLeft: Double { budget - totalSpent }

    /// 0…1 for the progress bars (capped at 1 when over budget).
    var spentFraction: Double { budget > 0 ? min(totalSpent / budget, 1) : 0 }

    var budgetStatus: BudgetStatus { ExpenseCalculator.budgetStatus(spent: totalSpent, budget: budget) }

    func spent(on category: ExpenseCategory) -> Double {
        expenses.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
    }

    func member(_ id: UUID) -> Member? { members.first { $0.id == id } }

    /// True when the member appears in an expense or payment, so removing them would break the maths.
    func hasMoney(involving member: Member) -> Bool {
        expenses.contains { $0.paidBy.id == member.id || $0.shares.contains { $0.member.id == member.id } }
            || payments.contains { $0.from.id == member.id || $0.to.id == member.id }
    }
}

// MARK: - Activity

enum Effort: String, CaseIterable, Identifiable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"

    var id: Self { self }
}

/// One item in the day-by-day itinerary.
struct Activity: Identifiable, Hashable {
    var id = UUID()
    var day: Int
    var title: String
    /// Minutes since midnight, e.g. 17:30 → 1050.
    var minutes: Int
    var place: String
    var effort: Effort
    var isOutdoor = false
    var isDone = false

    var timeText: String { minutes.clockText }
}

/// Badge shown above a day's schedule. Worked out by `ItineraryPlanner.intensity(of:)`.
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

    /// Icon so the badge doesn't rely on colour alone.
    var icon: String {
        switch self {
        case .easy: "figure.walk"
        case .moderate: "figure.hiking"
        case .demanding: "flame.fill"
        }
    }
}

// MARK: - PackingItem

struct PackingItem: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var category: String
    var isPacked = false
}

// MARK: - Expense

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

/// How much of an expense one member owes.
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
    /// Who owes what. The amounts always add up to `amount`.
    var shares: [ExpenseShare]
    var date: Date

    var participants: [Member] { shares.map(\.member) }

    func share(of member: Member) -> Double {
        shares.first { $0.member.id == member.id }?.amount ?? 0
    }
}

/// Money one member has paid another to settle up. Saved, unlike `Settlement`.
struct Payment: Identifiable, Hashable {
    var id = UUID()
    var from: Member
    var to: Member
    var amount: Double
    var date: Date
}

/// Net position of one member. Positive = gets money back, negative = owes.
struct Balance: Identifiable, Hashable {
    var member: Member
    var amount: Double

    var id: UUID { member.id }

    var text: String {
        if abs(amount) < 0.01 { return "\(member.name) is settled up" }
        return amount > 0 ? "\(member.name) gets back \(amount.lkr)" : "\(member.name) owes \((-amount).lkr)"
    }
}

/// A suggested payment that would settle the group up. Worked out, never saved.
struct Settlement: Identifiable, Hashable {
    var from: Member
    var to: Member
    var amount: Double

    var id: String { "\(from.id)-\(to.id)" }
}

/// How the spending compares with the budget.
enum BudgetStatus: Equatable {
    /// No budget was set (budget is 0).
    case noBudget
    case onTrack
    /// 90% or more of the budget is used.
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
