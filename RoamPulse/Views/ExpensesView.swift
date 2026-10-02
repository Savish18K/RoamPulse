import SwiftUI
import Charts

// MARK: - ExpensesView

struct ExpensesView: View {
    let tripID: UUID
    @Environment(TripStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let trip = store.trip(tripID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    budgetCard(trip)

                    if !trip.balances.isEmpty {
                        Text("Balances").font(.title3.bold())
                        VStack(spacing: 0) {
                            ForEach(trip.balances) { balance in
                                HStack(spacing: 12) {
                                    AvatarView(member: balance.member, size: 30)
                                    Text(balance.text)
                                        .foregroundStyle(balance.amount >= 0 ? .green : .primary)
                                    Spacer()
                                }
                                .padding(14)
                                if balance.id != trip.balances.last?.id {
                                    Divider().padding(.leading, 56)
                                }
                            }
                        }
                        .card(padding: 0)
                    }

                    ForEach(expenseDays(trip), id: \.self) { day in
                        SectionLabel(day.text("EEEE d MMM"))
                            .padding(.top, 6)
                        let expenses = trip.expenses
                            .filter { DemoClock.calendar.isDate($0.date, inSameDayAs: day) }
                            .sorted { $0.date > $1.date }
                        VStack(spacing: 0) {
                            ForEach(expenses) { expense in
                                ExpenseRow(expense: expense)
                                    .padding(.horizontal, 14)
                                if expense.id != expenses.last?.id {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                        .card(padding: 0)
                    }

                    if trip.expenses.isEmpty {
                        ContentUnavailableView("No expenses yet", systemImage: "creditcard",
                                               description: Text("Add the first shared cost for this trip."))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Expenses")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: settlementSummary(trip)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share settlement summary")
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                Button("+ Add Expense") { router.activeSheet = .addExpense(tripID: trip.id) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
        }
    }

    private func budgetCard(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SPENT BUDGET").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                NavigationLink("View Analytics", value: AppRoute.analytics(trip.id))
                    .font(.subheadline)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(trip.budgetLeft.lkr).font(.title.bold())
                Text("left of \(trip.budget.grouped)").font(.subheadline).foregroundStyle(.secondary)
            }
            ProgressView(value: trip.spentFraction)
                .tint(trip.spentFraction >= 0.9 ? .orange : .primary)
            if trip.spentFraction >= 0.9 {
                Label("You have used 90% of the budget.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .card()
    }

    private func expenseDays(_ trip: Trip) -> [Date] {
        let days = Set(trip.expenses.map { DemoClock.calendar.startOfDay(for: $0.date) })
        return days.sorted(by: >)
    }

    private func settlementSummary(_ trip: Trip) -> String {
        var lines = ["\(trip.name) — settle up", "Total spent: \(trip.totalSpent.lkr)"]
        lines += trip.settlements.map { "\($0.from.name) pays \($0.to.name) \($0.amount.lkr)" }
        return lines.joined(separator: "\n")
    }
}

/// One expense line: payer avatar (or category icon), title, who paid, amount.
struct ExpenseRow: View {
    let expense: Expense
    var showsCategoryIcon = false

    var body: some View {
        HStack(spacing: 12) {
            if showsCategoryIcon {
                Image(systemName: expense.category.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Circle().fill(expense.category.color).frame(width: 6, height: 6)
                AvatarView(member: expense.paidBy, size: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title).font(.headline).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(expense.amount.lkr).font(.subheadline.bold())
        }
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        let split = expense.paidBy.isMe || !expense.splitWith.contains(where: \.isMe)
            ? "Split equally"
            : "You owe \(expense.share.lkr)"
        return "Paid by \(expense.paidBy.name) • \(split)"
    }
}

#Preview {
    NavigationStack { ExpensesView(tripID: SampleData.hillCountry.id) }
        .environment(TripStore())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}

// MARK: - ExpenseAnalyticsView

struct ExpenseAnalyticsView: View {
    let tripID: UUID
    @Environment(TripStore.self) private var store
    @State private var mode = 0

    private struct DailyTotal: Identifiable {
        let date: Date
        let amount: Double
        var id: Date { date }
    }

    var body: some View {
        if let trip = store.trip(tripID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SegmentedTabs(options: ["Categories", "Daily"], selection: $mode)

                    if mode == 0 {
                        categoryCard(trip)
                    }
                    SectionLabel("Daily Spent")
                    dailyCard(trip)

                    Text("Settle-up Suggestions")
                        .font(.title3.bold())
                        .padding(.top, 8)
                    if trip.settlements.isEmpty {
                        Text("Everyone is settled up.").foregroundStyle(.secondary).card()
                    }
                    ForEach(trip.settlements) { settlement in
                        settlementRow(settlement, tripID: trip.id)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Analytics")
        }
    }

    private func categoryCard(_ trip: Trip) -> some View {
        HStack(spacing: 20) {
            Chart(ExpenseCategory.allCases) { category in
                SectorMark(
                    angle: .value("Amount", trip.spent(on: category)),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .foregroundStyle(category.color)
            }
            .frame(width: 140, height: 140)
            .overlay {
                VStack(spacing: 0) {
                    Text("TOTAL").font(.caption2).foregroundStyle(.secondary)
                    Text(trip.totalSpent.compact).font(.title3.bold())
                }
            }
            .accessibilityLabel("Total spent \(trip.totalSpent.lkr)")

            VStack(alignment: .leading, spacing: 10) {
                ForEach(ExpenseCategory.allCases) { category in
                    HStack {
                        Circle().fill(category.color).frame(width: 8, height: 8)
                        Text(category.rawValue).font(.subheadline.bold())
                        Spacer()
                        Text(trip.spent(on: category).lkr)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card(padding: 20)
    }

    private func dailyCard(_ trip: Trip) -> some View {
        let totals = Dictionary(grouping: trip.expenses) { DemoClock.calendar.startOfDay(for: $0.date) }
            .map { DailyTotal(date: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.date < $1.date }

        return Chart(totals) { total in
            BarMark(
                x: .value("Day", total.date.text("EEE d")),
                y: .value("Spent", total.amount),
                width: .fixed(56)
            )
            .foregroundStyle(mode == 1 ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.primary))
            .cornerRadius(8)
            .annotation(position: .top) {
                Text(total.amount.grouped).font(.caption).foregroundStyle(.secondary)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: mode == 1 ? 260 : 170)
        .card(padding: 20)
    }

    private func settlementRow(_ settlement: Settlement, tripID: UUID) -> some View {
        HStack(spacing: 10) {
            AvatarView(member: settlement.from, size: 36)
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
            AvatarView(member: settlement.to, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(settlement.amount.lkr).font(.headline)
                Text("\(settlement.from.name) to \(settlement.to.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            Spacer()
            Button {
                withAnimation { store.toggleSettled(settlement.id, in: tripID) }
            } label: {
                Label(settlement.isSettled ? "Settled" : "Settle",
                      systemImage: settlement.isSettled ? "checkmark" : "arrow.left.arrow.right")
                    .labelStyle(.titleOnly)
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: false, height: 36))
        }
        .opacity(settlement.isSettled ? 0.5 : 1)
        .card(padding: 14)
    }
}

#Preview {
    NavigationStack { ExpenseAnalyticsView(tripID: SampleData.hillCountry.id) }
        .environment(TripStore())
        .preferredColorScheme(.dark)
}

// MARK: - AddExpenseView

/// Add Expense sheet with its own number pad, like the prototype.
struct AddExpenseView: View {
    let tripID: UUID

    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var note = ""
    @State private var category: ExpenseCategory = .transport
    @State private var paidByID: UUID?
    @State private var excludedIDs: Set<UUID> = []

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]

    private var trip: Trip? { store.trip(tripID) }
    private var members: [Member] { trip?.members ?? [] }
    private var amount: Double { Double(amountText) ?? 0 }
    private var paidBy: Member? { members.first { $0.id == paidByID } ?? members.first(where: \.isMe) ?? members.first }
    private var splitWith: [Member] { members.filter { !excludedIDs.contains($0.id) } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        amountDisplay

                        TextField("Tuk-tuk to Nine Arch Bridge", text: $note)
                            .fieldStyle()

                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Category")
                            FlowLayout {
                                ForEach(ExpenseCategory.allCases) { item in
                                    Button { category = item } label: { categoryChip(item) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Paid By")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(members) { member in
                                        Button { paidByID = member.id } label: { payerChip(member) }
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        splitSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                keypad
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
    }

    // MARK: - Sections

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("LKR").font(.title.bold()).foregroundStyle(.secondary)
            Text(displayAmount)
                .font(.system(size: 56, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }

    private func categoryChip(_ item: ExpenseCategory) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(category == item ? .white : item.color)
                .frame(width: 8, height: 8)
            Text(item.rawValue)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(category == item ? .white : .primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(category == item ? Color.blue : Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }

    private func payerChip(_ member: Member) -> some View {
        let isSelected = paidBy?.id == member.id
        return HStack(spacing: 8) {
            AvatarView(member: member, size: 30)
            Text(member.name).font(.subheadline.weight(isSelected ? .semibold : .regular))
        }
        .padding(6)
        .padding(.trailing, 8)
        .background(isSelected ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isSelected ? Color.blue : .clear, lineWidth: 1.5))
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Split With")
                Text("Split equally").font(.subheadline).foregroundStyle(.green)
            }
            HStack(spacing: 12) {
                HStack(spacing: -10) {
                    ForEach(members) { member in
                        Button {
                            if excludedIDs.contains(member.id) {
                                excludedIDs.remove(member.id)
                            } else if splitWith.count > 1 {
                                excludedIDs.insert(member.id)
                            }
                        } label: {
                            AvatarView(member: member, size: 40)
                                .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
                                .opacity(excludedIDs.contains(member.id) ? 0.3 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(splitSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var splitSummary: String {
        let count = splitWith.count
        let who = count == members.count ? "All \(count) members active" : "\(count) of \(members.count) members"
        return "\(who) • \((amount / Double(max(count, 1))).lkr) each"
    }

    // MARK: - Keypad

    private var keypad: some View {
        VStack(spacing: 10) {
            Button("Add \(amount.lkr)", action: add)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(amount <= 0)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    Button {
                        press(key)
                    } label: {
                        Group {
                            if key == "⌫" {
                                Image(systemName: "delete.left")
                            } else {
                                Text(key)
                            }
                        }
                        .font(.title2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(key == "⌫" ? "Delete" : key)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .background(Theme.card)
        .sensoryFeedback(.impact(weight: .light), trigger: amountText)
    }

    private var displayAmount: String {
        guard !amountText.isEmpty else { return "0" }
        let parts = amountText.split(separator: ".", omittingEmptySubsequences: false)
        let whole = (Double(parts[0]) ?? 0).grouped
        return parts.count > 1 ? "\(whole).\(parts[1])" : whole
    }

    private func press(_ key: String) {
        switch key {
        case "⌫":
            if !amountText.isEmpty { amountText.removeLast() }
        case ".":
            if !amountText.contains(".") { amountText += amountText.isEmpty ? "0." : "." }
        default:
            if let dot = amountText.firstIndex(of: "."), amountText.distance(from: dot, to: amountText.endIndex) > 2 { return }
            if amountText.count >= 9 { return }
            if amountText == "0" { amountText = key } else { amountText += key }
        }
    }

    private func add() {
        guard let paidBy else { return }
        let expense = Expense(
            title: note.trimmingCharacters(in: .whitespaces).isEmpty ? category.rawValue : note,
            amount: amount,
            category: category,
            paidBy: paidBy,
            splitWith: splitWith,
            date: DemoClock.now
        )
        store.addExpense(expense, to: tripID)
        dismiss()
    }
}

#Preview {
    Text("Expenses")
        .sheet(isPresented: .constant(true)) {
            AddExpenseView(tripID: SampleData.hillCountry.id).environment(TripStore())
        }
        .preferredColorScheme(.dark)
}
