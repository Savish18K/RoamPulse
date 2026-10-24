import Foundation

// Expense maths, done in cents to avoid floating point rounding errors
enum ExpenseCalculator {

    static func toCents(_ amount: Double) -> Int { Int((amount * 100).rounded()) }

    static func fromCents(_ cents: Int) -> Double { Double(cents) / 100 }

    // Leftover cents go to the first people, e.g. 100 / 3 -> 33.34, 33.33, 33.33
    static func equalShares(of amount: Double, between members: [Member]) -> [ExpenseShare] {
        guard !members.isEmpty else { return [] }
        let total = toCents(amount)
        let base = total / members.count
        let leftover = total % members.count
        return members.enumerated().map { index, member in
            ExpenseShare(member: member, amount: fromCents(base + (index < leftover ? 1 : 0)))
        }
    }

    // 0 = all assigned, negative = too much given out
    static func unassigned(total: Double, shares: [Double]) -> Double {
        fromCents(toCents(total) - shares.map(toCents).reduce(0, +))
    }

    // Positive = owed money, negative = owes. All balances add up to 0
    static func balances(members: [Member], expenses: [Expense], payments: [Payment]) -> [Balance] {
        var net: [UUID: Int] = [:]
        for expense in expenses {
            net[expense.paidBy.id, default: 0] += toCents(expense.amount)
            for share in expense.shares {
                net[share.member.id, default: 0] -= toCents(share.amount)
            }
        }
        // A payment works like a loan: payer goes up, receiver goes down
        for payment in payments {
            net[payment.from.id, default: 0] += toCents(payment.amount)
            net[payment.to.id, default: 0] -= toCents(payment.amount)
        }
        return members.map { Balance(member: $0, amount: fromCents(net[$0.id] ?? 0)) }
    }

    static func balances(for trip: Trip) -> [Balance] {
        balances(members: trip.members, expenses: trip.expenses, payments: trip.payments)
    }

    private struct Position {
        let member: Member
        var cents: Int
    }

    // Greedy: biggest debtor pays biggest creditor, at most n - 1 payments
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

    // Ties sorted by name so the plan is always the same
    private static func largestFirst(_ a: Position, _ b: Position) -> Bool {
        a.cents != b.cents ? a.cents > b.cents : a.member.name < b.member.name
    }

    static let warningPercent = 90

    static func budgetStatus(spent: Double, budget: Double) -> BudgetStatus {
        let spentCents = toCents(spent)
        let budgetCents = toCents(budget)
        guard budgetCents > 0 else { return .noBudget }
        if spentCents > budgetCents { return .overBudget }
        // Integer compare so exactly 90% counts
        if spentCents * 100 >= budgetCents * warningPercent { return .nearLimit }
        return .onTrack
    }
}
