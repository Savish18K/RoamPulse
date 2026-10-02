import SwiftUI

// MARK: - Member

/// A person travelling on a trip.
struct Member: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var initials: String
    var color: Color
    var isMe = false

    /// `initials` defaults to the first two letters, e.g. "Nimal" → "NI".
    init(name: String, initials: String? = nil, color: Color, isMe: Bool = false) {
        self.name = name
        self.initials = initials ?? String(name.prefix(2)).uppercased()
        self.color = color
        self.isMe = isMe
    }
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
    let id = UUID()
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
    // Mock values for now — these will come from the settlement algorithm.
    var balances: [Balance] = []
    var settlements: [Settlement] = []
    /// Days that have a weather advisory (shows an orange dot on the day tab).
    var advisoryDays: Set<Int> = []
}

// MARK: - Dates & status

extension Trip {
    var dayCount: Int { DemoClock.days(from: startDate, to: endDate) + 1 }

    func status(at now: Date = DemoClock.now) -> TripStatus {
        if DemoClock.days(from: now, to: startDate) > 0 { return .upcoming }
        if DemoClock.days(from: endDate, to: now) > 0 { return .completed }
        return .active
    }

    /// 1-based day number while the trip is active.
    func dayNumber(at now: Date = DemoClock.now) -> Int? {
        guard status(at: now) == .active else { return nil }
        return DemoClock.days(from: startDate, to: now) + 1
    }

    func daysUntilStart(from now: Date = DemoClock.now) -> Int {
        DemoClock.days(from: now, to: startDate)
    }

    func date(ofDay day: Int) -> Date {
        DemoClock.calendar.date(byAdding: .day, value: day - 1, to: startDate) ?? startDate
    }

    /// "Kandy → Ella"
    var routeText: String { destination.replacingOccurrences(of: " to ", with: " → ") }

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

    /// "Active • Day 2 of 4"
    var statusText: String {
        switch status() {
        case .active: "Active • Day \(dayNumber() ?? 1) of \(dayCount)"
        case .upcoming: "In \(daysUntilStart()) days"
        case .completed: "Completed"
        }
    }
}

// MARK: - Itinerary

extension Trip {
    func activities(onDay day: Int) -> [Activity] {
        activities.filter { $0.day == day }.sorted { $0.minutes < $1.minutes }
    }

    /// The next activity today that hasn't happened yet.
    func nextActivity(at now: Date = DemoClock.now) -> Activity? {
        guard let today = dayNumber(at: now) else { return nil }
        return activities(onDay: today).first { !$0.isDone && $0.minutes >= DemoClock.minutesNow }
    }

    func intensity(ofDay day: Int) -> DayIntensity? {
        let items = activities(onDay: day)
        if items.isEmpty { return nil }
        if items.contains(where: { $0.effort == .high }) { return .demanding }
        if items.contains(where: { $0.effort == .moderate }) { return .moderate }
        return .easy
    }
}

// MARK: - Packing & money

extension Trip {
    var packedCount: Int { packing.filter(\.isPacked).count }

    var packingProgress: Double { packing.isEmpty ? 0 : Double(packedCount) / Double(packing.count) }

    var totalSpent: Double { expenses.reduce(0) { $0 + $1.amount } }

    var budgetLeft: Double { budget - totalSpent }

    var spentFraction: Double { budget > 0 ? min(totalSpent / budget, 1) : 0 }

    func spent(on category: ExpenseCategory) -> Double {
        expenses.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
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
    let id = UUID()
    var day: Int
    var title: String
    /// Minutes since midnight, e.g. 17:30 → 1050.
    var minutes: Int
    var place: String
    var effort: Effort
    var isOutdoor = false
    var isDone = false
    /// Weather advisory text shown under the activity (mock for now).
    var advisory: String?

    var timeText: String { minutes.clockText }
}

/// Badge shown above a day's schedule.
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
}

// MARK: - PackingItem

struct PackingItem: Identifiable, Hashable {
    let id = UUID()
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

struct Expense: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var amount: Double
    var category: ExpenseCategory
    var paidBy: Member
    var splitWith: [Member]
    var date: Date

    /// Equal share for each person in `splitWith`.
    var share: Double { amount / Double(max(splitWith.count, 1)) }
}

/// Net position of one member. Positive = gets money back, negative = owes.
struct Balance: Identifiable, Hashable {
    let id = UUID()
    var member: Member
    var amount: Double

    var text: String {
        amount >= 0 ? "\(member.name) gets back \(amount.lkr)" : "\(member.name) owes \((-amount).lkr)"
    }
}

/// A suggested payment to settle up.
struct Settlement: Identifiable, Hashable {
    let id = UUID()
    var from: Member
    var to: Member
    var amount: Double
    var isSettled = false
}
