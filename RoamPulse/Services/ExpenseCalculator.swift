import Foundation

/// Money maths for a trip: splitting an expense, balances, the settle-up plan and the budget warning.
///
/// Amounts are stored as `Double`, but every calculation here is done in whole cents (`Int`).
/// That way rounding errors (e.g. 0.1 + 0.2 = 0.30000000000000004) can't build up,
/// and balances always add up to exactly zero.
enum ExpenseCalculator {

    static func toCents(_ amount: Double) -> Int { Int((amount * 100).rounded()) }

    static func fromCents(_ cents: Int) -> Double { Double(cents) / 100 }

    // MARK: - Splitting

    /// Splits `amount` equally. Any leftover cents go to the first people in the list,
    /// so the shares always add up to exactly the amount.
    /// e.g. LKR 100 between 3 people → 33.34, 33.33, 33.33.
    static func equalShares(of amount: Double, between members: [Member]) -> [ExpenseShare] {
        guard !members.isEmpty else { return [] }
        let total = toCents(amount)
        let base = total / members.count
        let leftover = total % members.count
        return members.enumerated().map { index, member in
            ExpenseShare(member: member, amount: fromCents(base + (index < leftover ? 1 : 0)))
        }
    }

    /// For a custom split: how much of the expense is not yet given to anyone.
    /// 0 means the shares add up exactly; negative means too much has been given out.
    static func unassigned(total: Double, shares: [Double]) -> Double {
        fromCents(toCents(total) - shares.map(toCents).reduce(0, +))
    }

    // MARK: - Balances

    /// Each member's net balance: what they paid, minus their share of every expense,
    /// adjusted by the settle-up payments already made.
    ///
    /// Positive = the group owes them money, negative = they owe the group.
    /// Because every expense's shares add up to its amount, the balances always add up to 0.
    static func balances(members: [Member], expenses: [Expense], payments: [Payment]) -> [Balance] {
        var net: [UUID: Int] = [:]
        for expense in expenses {
            net[expense.paidBy.id, default: 0] += toCents(expense.amount)
            for share in expense.shares {
                net[share.member.id, default: 0] -= toCents(share.amount)
            }
        }
        // Paying someone back is like lending them that money: the payer goes up, the receiver goes down.
        for payment in payments {
            net[payment.from.id, default: 0] += toCents(payment.amount)
            net[payment.to.id, default: 0] -= toCents(payment.amount)
        }
        return members.map { Balance(member: $0, amount: fromCents(net[$0.id] ?? 0)) }
    }

    static func balances(for trip: Trip) -> [Balance] {
        balances(members: trip.members, expenses: trip.expenses, payments: trip.payments)
    }

    // MARK: - Settle up

    /// One side of the settle-up: a member and how much they owe or are owed, in cents.
    private struct Position {
        let member: Member
        var cents: Int
    }

    /// The settle-up plan (greedy algorithm).
    ///
    /// Repeatedly match the person who owes the most with the person who is owed the most,
    /// and have them pay the smaller of the two amounts. Each payment clears at least one
    /// person, so a group of n people needs at most n − 1 payments.
    static func settlements(for balances: [Balance]) -> [Settlement] {
        var debtors = balances
            .filter { toCents($0.amount) < 0 }
            .map { Position(member: $0.member, cents: -toCents($0.amount)) }
        var creditors = balances
            .filter { toCents($0.amount) > 0 }
            .map { Position(member: $0.member, cents: toCents($0.amount)) }
        var plan: [Settlement] = []

        while !debtors.isEmpty && !creditors.isEmpty {
            debtors.sort(by: largestFirst)
            creditors.sort(by: largestFirst)

            let payment = min(debtors[0].cents, creditors[0].cents)
            plan.append(Settlement(from: debtors[0].member, to: creditors[0].member, amount: fromCents(payment)))

            debtors[0].cents -= payment
            creditors[0].cents -= payment
            debtors.removeAll { $0.cents == 0 }
            creditors.removeAll { $0.cents == 0 }
        }
        return plan
    }

    static func settlements(for trip: Trip) -> [Settlement] {
        settlements(for: balances(for: trip))
    }

    /// Biggest amount first. Ties go in name order, so the plan is the same every time.
    private static func largestFirst(_ a: Position, _ b: Position) -> Bool {
        a.cents != b.cents ? a.cents > b.cents : a.member.name < b.member.name
    }

    // MARK: - Budget

    /// The budget warning shows once this share of the budget is spent.
    static let warningPercent = 90

    static func budgetStatus(spent: Double, budget: Double) -> BudgetStatus {
        let spentCents = toCents(spent)
        let budgetCents = toCents(budget)
        guard budgetCents > 0 else { return .noBudget }
        if spentCents > budgetCents { return .overBudget }
        // Compared as whole numbers (spent × 100 ≥ budget × 90) so 90% exactly always counts.
        if spentCents * 100 >= budgetCents * warningPercent { return .nearLimit }
        return .onTrack
    }
}
