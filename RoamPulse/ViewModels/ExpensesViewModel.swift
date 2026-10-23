import Foundation
import Observation

/// Expenses screen: budget card, balances and the expenses grouped by day.
@MainActor
@Observable
final class ExpensesViewModel {
    let tripID: UUID
    private let store: TripStore

    /// The expense waiting for the user to confirm the delete.
    var expensePendingDelete: Expense?

    init(tripID: UUID, store: TripStore) {
        self.tripID = tripID
        self.store = store
    }

    var trip: Trip? { store.trip(tripID) }

    var budgetStatus: BudgetStatus { trip?.budgetStatus ?? .noBudget }

    var spentFraction: Double { trip?.spentFraction ?? 0 }

    var headline: String {
        guard let trip else { return "" }
        switch budgetStatus {
        case .noBudget: return trip.totalSpent.lkr
        case .overBudget: return (-trip.budgetLeft).lkr
        case .onTrack, .nearLimit: return trip.budgetLeft.lkr
        }
    }

    var headlineCaption: String {
        guard let trip else { return "" }
        switch budgetStatus {
        case .noBudget: return "spent • no budget set"
        case .overBudget: return "over the \(trip.budget.grouped) budget"
        case .onTrack, .nearLimit: return "left of \(trip.budget.grouped)"
        }
    }

    /// Who is owed the most first.
    var balances: [Balance] {
        guard let trip, !trip.expenses.isEmpty else { return [] }
        return ExpenseCalculator.balances(for: trip).sorted { $0.amount > $1.amount }
    }

    struct ExpenseDay: Identifiable {
        let day: Date
        let expenses: [Expense]
        var id: Date { day }
    }

    /// Expenses grouped by calendar day, newest day first.
    var expenseDays: [ExpenseDay] {
        let calendar = Calendar.trip
        let groups = Dictionary(grouping: trip?.expenses ?? []) { calendar.startOfDay(for: $0.date) }
        return groups
            .map { ExpenseDay(day: $0.key, expenses: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var isEmpty: Bool { trip?.expenses.isEmpty ?? true }

    func requestDelete(_ expense: Expense) {
        expensePendingDelete = expense
    }

    func confirmDelete() {
        guard let expense = expensePendingDelete else { return }
        store.updateTrip(tripID) { trip in
            trip.expenses.removeAll { $0.id == expense.id }
        }
        expensePendingDelete = nil
    }

    /// Plain-text summary for the Share button (Messages, WhatsApp…).
    var shareSummary: String {
        guard let trip else { return "" }
        var lines = ["\(trip.name) — expenses", "Total spent: \(trip.totalSpent.lkr)"]
        if trip.budget > 0 {
            lines.append("Budget: \(trip.budget.lkr) (\(trip.spentFraction.percentText) used)")
        }
        lines.append("")
        lines.append("Balances")
        lines += balances.map { "• \($0.text)" }

        let plan = ExpenseCalculator.settlements(for: trip)
        lines.append("")
        if plan.isEmpty {
            lines.append("Everyone is settled up.")
        } else {
            lines.append("To settle up")
            lines += plan.map { "• \($0.from.name) pays \($0.to.name) \($0.amount.lkr)" }
        }
        lines.append("")
        lines.append("Sent from RoamPulse")
        return lines.joined(separator: "\n")
    }
}

/// Analytics: spending by category and by day, and the settle-up plan.
@MainActor
@Observable
final class ExpenseAnalyticsViewModel {
    let tripID: UUID
    private let store: TripStore
    private let clock: Clock

    init(tripID: UUID, store: TripStore, clock: Clock) {
        self.tripID = tripID
        self.store = store
        self.clock = clock
    }

    struct DailyTotal: Identifiable {
        let date: Date
        let amount: Double
        var id: Date { date }
    }

    var trip: Trip? { store.trip(tripID) }

    var totalSpent: Double { trip?.totalSpent ?? 0 }

    func spent(on category: ExpenseCategory) -> Double { trip?.spent(on: category) ?? 0 }

    var dailyTotals: [DailyTotal] {
        let calendar = Calendar.trip
        let groups = Dictionary(grouping: trip?.expenses ?? []) { calendar.startOfDay(for: $0.date) }
        return groups
            .map { DailyTotal(date: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.date < $1.date }
    }

    /// The fewest payments that would settle everyone up.
    var settlements: [Settlement] {
        guard let trip else { return [] }
        return ExpenseCalculator.settlements(for: trip)
    }

    /// Payments already made, newest first.
    var payments: [Payment] { (trip?.payments ?? []).sorted { $0.date > $1.date } }

    /// Records the payment, so the balances and the plan update.
    func settle(_ settlement: Settlement) {
        let payment = Payment(from: settlement.from, to: settlement.to, amount: settlement.amount, date: clock.now)
        store.updateTrip(tripID) { $0.payments.append(payment) }
    }

    func undo(_ payment: Payment) {
        store.updateTrip(tripID) { trip in
            trip.payments.removeAll { $0.id == payment.id }
        }
    }
}

/// Add Expense and Edit Expense sheet, with its own number pad and equal or custom splits.
@MainActor
@Observable
final class ExpenseFormViewModel {
    /// Which amount the number pad is typing into.
    enum Field: Hashable {
        case total
        case share(UUID)
    }

    let tripID: UUID
    /// The expense being edited, or nil when adding a new one.
    let expenseID: UUID?
    private let store: TripStore
    private let clock: Clock

    var note = ""
    var category: ExpenseCategory = .transport
    var payerID: UUID?
    private(set) var splitMethod: SplitMethod = .equal
    /// Equal split: the members who are left out.
    private(set) var excludedIDs: Set<UUID> = []
    var activeField: Field = .total
    private(set) var totalText = ""
    /// Custom split: what each member typed.
    private(set) var shareTexts: [UUID: String] = [:]

    init(tripID: UUID, expenseID: UUID? = nil, store: TripStore, clock: Clock) {
        self.tripID = tripID
        self.expenseID = expenseID
        self.store = store
        self.clock = clock

        guard let expenseID, let trip = store.trip(tripID),
              let expense = trip.expenses.first(where: { $0.id == expenseID }) else { return }
        totalText = AmountInput.text(for: expense.amount)
        note = expense.title
        category = expense.category
        payerID = expense.paidBy.id
        splitMethod = expense.splitMethod
        let participantIDs = Set(expense.participants.map(\.id))
        excludedIDs = Set(trip.members.map(\.id)).subtracting(participantIDs)
        if expense.splitMethod == .custom {
            for share in expense.shares {
                shareTexts[share.member.id] = AmountInput.text(for: share.amount)
            }
        }
    }

    var isEditing: Bool { expenseID != nil }
    var screenTitle: String { isEditing ? "Edit Expense" : "Add Expense" }

    var members: [Member] { store.trip(tripID)?.members ?? [] }

    /// The chosen payer, or you, or the first member.
    var payer: Member? {
        members.first { $0.id == payerID } ?? members.first(where: \.isMe) ?? members.first
    }

    var amount: Double { Double(totalText) ?? 0 }

    var equalParticipants: [Member] { members.filter { !excludedIDs.contains($0.id) } }

    func isIncluded(_ member: Member) -> Bool { !excludedIDs.contains(member.id) }

    /// Taps on an avatar. At least one person always stays in the split.
    func toggleParticipant(_ member: Member) {
        if excludedIDs.contains(member.id) {
            excludedIDs.remove(member.id)
        } else if equalParticipants.count > 1 {
            excludedIDs.insert(member.id)
        }
    }

    var equalSummary: String {
        let count = equalParticipants.count
        let who = count == members.count ? "All \(count) members" : "\(count) of \(members.count) members"
        let each = ExpenseCalculator.equalShares(of: amount, between: equalParticipants).first?.amount ?? 0
        return "\(who) • \(each.lkr) each"
    }

    func setSplitMethod(_ method: SplitMethod) {
        splitMethod = method
        activeField = .total
        // Start the custom split from an equal split, so the user only adjusts the differences.
        if method == .custom && shareTexts.isEmpty && amount > 0 {
            for share in ExpenseCalculator.equalShares(of: amount, between: members) {
                shareTexts[share.member.id] = AmountInput.text(for: share.amount)
            }
        }
    }

    func shareAmount(for member: Member) -> Double { Double(shareTexts[member.id] ?? "") ?? 0 }

    /// Money not yet given to anyone. Negative when the shares add up to too much.
    var unassigned: Double {
        ExpenseCalculator.unassigned(total: amount, shares: members.map(shareAmount))
    }

    var customSummary: String {
        if unassigned == 0 { return "Shares add up to \(amount.lkr)" }
        return unassigned > 0 ? "\(unassigned.lkr) left to assign" : "\((-unassigned).lkr) too much"
    }

    /// Who owes what, from the chosen split. Always adds up to `amount` when valid.
    var shares: [ExpenseShare] {
        switch splitMethod {
        case .equal:
            return ExpenseCalculator.equalShares(of: amount, between: equalParticipants)
        case .custom:
            return members
                .map { ExpenseShare(member: $0, amount: shareAmount(for: $0)) }
                .filter { $0.amount > 0 }
        }
    }

    /// Why the expense can't be saved yet, if there is a reason worth showing.
    var validationMessage: String? {
        guard amount > 0, splitMethod == .custom else { return nil }
        if shares.isEmpty { return "Give at least one person a share." }
        if unassigned != 0 { return "The shares must add up to \(amount.lkr)." }
        return nil
    }

    var canSave: Bool { amount > 0 && payer != nil && !shares.isEmpty && validationMessage == nil }

    var saveTitle: String { "\(isEditing ? "Save" : "Add") \(amount.lkr)" }

    func text(for field: Field) -> String {
        switch field {
        case .total: AmountInput.display(totalText)
        case .share(let id): AmountInput.display(shareTexts[id] ?? "")
        }
    }

    func press(_ key: String) {
        switch activeField {
        case .total:
            totalText = AmountInput.apply(key, to: totalText)
        case .share(let id):
            shareTexts[id] = AmountInput.apply(key, to: shareTexts[id] ?? "")
        }
    }

    /// Returns false if the form isn't valid or saving failed.
    func save() -> Bool {
        guard canSave, let payer else { return false }
        let title = note.trimmed.isEmpty ? category.rawValue : note.trimmed

        guard let expenseID else {
            let expense = Expense(title: title, amount: amount, category: category, paidBy: payer,
                                  splitMethod: splitMethod, shares: shares, date: clock.now)
            return store.updateTrip(tripID) { $0.expenses.append(expense) }
        }

        return store.updateTrip(tripID) { trip in
            guard let index = trip.expenses.firstIndex(where: { $0.id == expenseID }) else { return }
            trip.expenses[index].title = title
            trip.expenses[index].amount = amount
            trip.expenses[index].category = category
            trip.expenses[index].paidBy = payer
            trip.expenses[index].splitMethod = splitMethod
            trip.expenses[index].shares = shares
        }
    }
}

/// Rules for typing an amount on the number pad: one decimal point, at most
/// two decimal places and nine digits.
enum AmountInput {
    static let deleteKey = "⌫"
    static let maxDigits = 9

    static func apply(_ key: String, to text: String) -> String {
        switch key {
        case deleteKey:
            return String(text.dropLast())
        case ".":
            if text.contains(".") { return text }
            return text.isEmpty ? "0." : text + "."
        default:
            guard key.count == 1, key.first?.isNumber == true else { return text }
            if let dot = text.firstIndex(of: "."), text.distance(from: dot, to: text.endIndex) > 2 { return text }
            if text.filter(\.isNumber).count >= maxDigits { return text }
            return text == "0" ? key : text + key
        }
    }

    /// "12500.5" → "12,500.5", "" → "0".
    static func display(_ text: String) -> String {
        guard !text.isEmpty else { return "0" }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = (Double(parts[0]) ?? 0).grouped
        return parts.count > 1 ? "\(whole).\(parts[1])" : whole
    }

    /// The text the number pad starts with when editing, e.g. 6200 → "6200", 33.5 → "33.5".
    static func text(for amount: Double) -> String {
        let cents = ExpenseCalculator.toCents(amount)
        if cents % 100 == 0 { return String(cents / 100) }
        return String(format: "%.2f", amount).replacingOccurrences(of: ".?0+$", with: "", options: .regularExpression)
    }
}
