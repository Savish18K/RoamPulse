import Foundation
import Testing
@testable import RoamPulse

struct ExpenseCalculatorTests {
    let savishka = Member(name: "Savishka", colorHex: 0, isMe: true)
    let samee = Member(name: "Samee", colorHex: 0)
    let suu = Member(name: "Suu", colorHex: 0)
    let suresha = Member(name: "Suresha", colorHex: 0)

    var crew: [Member] { [savishka, samee, suu, suresha] }

    private func expense(_ amount: Double, paidBy: Member, splitWith: [Member]) -> Expense {
        Expense(title: "Test", amount: amount, category: .food, paidBy: paidBy,
                shares: ExpenseCalculator.equalShares(of: amount, between: splitWith), date: .now)
    }

    private func amount(for member: Member, in balances: [Balance]) -> Double? {
        balances.first { $0.member.id == member.id }?.amount
    }

    // The 9 expenses from the prototype trip
    private var prototypeExpenses: [Expense] {
        [
            expense(14_000, paidBy: savishka, splitWith: crew),
            expense(12_000, paidBy: suresha, splitWith: crew),
            expense(2_500, paidBy: samee, splitWith: crew),
            expense(2_500, paidBy: suu, splitWith: crew),
            expense(3_400, paidBy: samee, splitWith: crew),
            expense(6_200, paidBy: suresha, splitWith: crew),
            expense(6_800, paidBy: samee, splitWith: crew),
            expense(18_000, paidBy: savishka, splitWith: crew),
            expense(3_000, paidBy: suu, splitWith: crew),
        ]
    }

    @Test func equalSplitGivesLeftoverCentsToTheFirstPeople() {
        let shares = ExpenseCalculator.equalShares(of: 100, between: [savishka, samee, suu])
        #expect(shares.map(\.amount) == [33.34, 33.33, 33.33])
    }

    @Test(arguments: [0.01, 10, 99.99, 1_000, 68_400, 12_345.67])
    func equalSharesAlwaysAddUpToTheAmount(amount: Double) {
        let shares = ExpenseCalculator.equalShares(of: amount, between: crew)
        let totalCents = shares.map { ExpenseCalculator.toCents($0.amount) }.reduce(0, +)
        #expect(totalCents == ExpenseCalculator.toCents(amount))
    }

    @Test func splittingBetweenNobodyGivesNoShares() {
        #expect(ExpenseCalculator.equalShares(of: 500, between: []).isEmpty)
    }

    @Test func unassignedShowsWhatIsLeftOrTooMuch() {
        #expect(ExpenseCalculator.unassigned(total: 1_000, shares: [400, 600]) == 0)
        #expect(ExpenseCalculator.unassigned(total: 1_000, shares: [400, 500]) == 100)
        #expect(ExpenseCalculator.unassigned(total: 1_000, shares: [700, 600]) == -300)
        // 0.1 + 0.2 isn't exactly 0.3 as a Double, cents fixes that
        #expect(ExpenseCalculator.unassigned(total: 0.3, shares: [0.1, 0.2]) == 0)
    }

    @Test func balancesMatchThePrototypeTrip() {
        let balances = ExpenseCalculator.balances(members: crew, expenses: prototypeExpenses, payments: [])
        #expect(amount(for: savishka, in: balances) == 14_900)
        #expect(amount(for: suresha, in: balances) == 1_100)
        #expect(amount(for: samee, in: balances) == -4_400)
        #expect(amount(for: suu, in: balances) == -11_600)
    }

    @Test func balancesAlwaysAddUpToZero() {
        let expenses = [
            expense(100, paidBy: savishka, splitWith: [savishka, samee, suu]),
            expense(250.55, paidBy: suu, splitWith: crew),
            expense(19.99, paidBy: suresha, splitWith: [samee, suresha]),
        ]
        let balances = ExpenseCalculator.balances(members: crew, expenses: expenses, payments: [])
        let totalCents = balances.map { ExpenseCalculator.toCents($0.amount) }.reduce(0, +)
        #expect(totalCents == 0)
    }

    @Test func customSplitOnlyChargesThePeopleInIt() {
        let dinner = Expense(title: "Dinner", amount: 3_000, category: .food, paidBy: samee, splitMethod: .custom,
                             shares: [ExpenseShare(member: samee, amount: 1_000), ExpenseShare(member: suu, amount: 2_000)],
                             date: .now)
        let balances = ExpenseCalculator.balances(members: crew, expenses: [dinner], payments: [])
        #expect(amount(for: samee, in: balances) == 2_000)
        #expect(amount(for: suu, in: balances) == -2_000)
        #expect(amount(for: savishka, in: balances) == 0)
        #expect(amount(for: suresha, in: balances) == 0)
    }

    @Test func aPaymentMovesBothBalancesTowardsZero() {
        let lunch = expense(1_000, paidBy: savishka, splitWith: [savishka, samee])
        let payBack = Payment(from: samee, to: savishka, amount: 500, date: .now)
        let balances = ExpenseCalculator.balances(members: [savishka, samee], expenses: [lunch], payments: [payBack])
        #expect(balances.allSatisfy { $0.amount == 0 })
    }

    @Test func settlementMatchesThePrototype() {
        let balances = ExpenseCalculator.balances(members: crew, expenses: prototypeExpenses, payments: [])
        let plan = ExpenseCalculator.settlements(for: balances)

        // Suu owes the most and Savishka is owed the most, so Suu pays first
        #expect(plan.map(\.from.name) == ["Suu", "Samee", "Samee"])
        #expect(plan.map(\.to.name) == ["Savishka", "Savishka", "Suresha"])
        #expect(plan.map(\.amount) == [11_600, 3_300, 1_100])
    }

    @Test func followingThePlanClearsEveryBalance() {
        let expenses = [
            expense(100, paidBy: savishka, splitWith: [savishka, samee, suu]),
            expense(250.55, paidBy: suu, splitWith: crew),
            expense(19.99, paidBy: suresha, splitWith: [samee, suresha]),
            expense(4_000, paidBy: samee, splitWith: crew),
        ]
        let before = ExpenseCalculator.balances(members: crew, expenses: expenses, payments: [])
        let plan = ExpenseCalculator.settlements(for: before)

        // After paying the plan nobody should owe anything
        let payments = plan.map { Payment(from: $0.from, to: $0.to, amount: $0.amount, date: .now) }
        let after = ExpenseCalculator.balances(members: crew, expenses: expenses, payments: payments)
        #expect(after.allSatisfy { ExpenseCalculator.toCents($0.amount) == 0 })

        // and it shouldn't need more than n - 1 payments
        #expect(plan.count <= crew.count - 1)
    }

    @Test func noPaymentsWhenEveryoneIsEven() {
        let balances = crew.map { Balance(member: $0, amount: 0) }
        #expect(ExpenseCalculator.settlements(for: balances).isEmpty)
    }

    @Test func aTripWithNoExpensesHasNoPlan() {
        let balances = ExpenseCalculator.balances(members: crew, expenses: [], payments: [])
        #expect(balances.allSatisfy { $0.amount == 0 })
        #expect(ExpenseCalculator.settlements(for: balances).isEmpty)
    }

    @Test func aSoloTravellerNeverPaysThemselves() {
        let hotel = expense(18_000, paidBy: savishka, splitWith: [savishka])
        let balances = ExpenseCalculator.balances(members: [savishka], expenses: [hotel], payments: [])
        #expect(amount(for: savishka, in: balances) == 0)
        #expect(ExpenseCalculator.settlements(for: balances).isEmpty)
    }

    @Test func tiesAreSettledInNameOrder() {
        // Same amount owed, so alphabetical order decides
        let balances = [
            Balance(member: savishka, amount: 200),
            Balance(member: suu, amount: -100),
            Balance(member: samee, amount: -100),
        ]
        let plan = ExpenseCalculator.settlements(for: balances)
        #expect(plan.map(\.from.name) == ["Samee", "Suu"])
    }

    @Test func budgetWarningStartsAtNinetyPercent() {
        #expect(ExpenseCalculator.budgetStatus(spent: 89_999, budget: 100_000) == .onTrack)
        #expect(ExpenseCalculator.budgetStatus(spent: 90_000, budget: 100_000) == .nearLimit)
        #expect(ExpenseCalculator.budgetStatus(spent: 100_000, budget: 100_000) == .nearLimit)
        #expect(ExpenseCalculator.budgetStatus(spent: 100_001, budget: 100_000) == .overBudget)
    }

    @Test func aZeroBudgetNeverWarns() {
        #expect(ExpenseCalculator.budgetStatus(spent: 0, budget: 0) == .noBudget)
        #expect(ExpenseCalculator.budgetStatus(spent: 5_000, budget: 0) == .noBudget)
    }
}
