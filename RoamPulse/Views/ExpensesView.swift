import SwiftUI
import Charts

struct ExpensesView: View {
    @State private var viewModel: ExpensesViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: ExpensesViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        if let trip = viewModel.trip {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    budgetCard(trip)

                    if !viewModel.balances.isEmpty {
                        Text("Balances").font(.title3.bold())
                        VStack(spacing: 0) {
                            ForEach(viewModel.balances) { balance in
                                HStack(spacing: 12) {
                                    AvatarView(member: balance.member, size: 30)
                                    Text(balance.text)
                                        .foregroundStyle(balance.amount > 0 ? .green : .primary)
                                    Spacer()
                                }
                                .padding(14)
                                if balance.id != viewModel.balances.last?.id {
                                    Divider().padding(.leading, 56)
                                }
                            }
                        }
                        .card(padding: 0)
                    }

                    ForEach(viewModel.expenseDays) { group in
                        SectionLabel(group.day.text("EEEE d MMM"))
                            .padding(.top, 6)
                        VStack(spacing: 0) {
                            ForEach(group.expenses) { expense in
                                Button {
                                    router.activeSheet = .editExpense(tripID: trip.id, expenseID: expense.id)
                                } label: {
                                    ExpenseRow(expense: expense)
                                        .padding(.horizontal, 14)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu { expenseMenu(expense, trip: trip) }
                                if expense.id != group.expenses.last?.id {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                        .card(padding: 0)
                    }

                    if viewModel.isEmpty {
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
                    ShareLink(item: viewModel.shareSummary, subject: Text("\(trip.name) expenses")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share expense summary")
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                Button("+ Add Expense") { router.activeSheet = .addExpense(tripID: trip.id) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            .confirmationDialog(
                "Delete this expense?",
                isPresented: Binding(
                    get: { viewModel.expensePendingDelete != nil },
                    set: { if !$0 { viewModel.expensePendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: viewModel.expensePendingDelete
            ) { expense in
                Button("Delete \(expense.title)", role: .destructive) {
                    withAnimation { viewModel.confirmDelete() }
                }
            } message: { _ in
                Text("Balances and the settle-up plan will be worked out again.")
            }
        }
    }

    private func budgetCard(_ trip: Trip) -> some View {
        let status = viewModel.budgetStatus
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SPENT BUDGET").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                NavigationLink("View Analytics", value: AppRoute.analytics(trip.id))
                    .font(.subheadline)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(viewModel.headline)
                    .font(.title.bold())
                    .foregroundStyle(status == .overBudget ? .red : .primary)
                Text(viewModel.headlineCaption).font(.subheadline).foregroundStyle(.secondary)
            }
            if status != .noBudget {
                ProgressView(value: viewModel.spentFraction)
                    .tint(status.color)
                    .accessibilityLabel("Budget used")
                    .accessibilityValue(viewModel.spentFraction.percentText)
            }
            if let message = status.message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(status.color)
            }
        }
        .card()
    }

    @ViewBuilder
    private func expenseMenu(_ expense: Expense, trip: Trip) -> some View {
        Button {
            router.activeSheet = .editExpense(tripID: trip.id, expenseID: expense.id)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button(role: .destructive) {
            viewModel.requestDelete(expense)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

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

    // e.g. "Paid by Samee • You owe LKR 850"
    private var subtitle: String {
        if !expense.paidBy.isMe, let me = expense.participants.first(where: \.isMe) {
            return "Paid by \(expense.paidBy.name) • You owe \(expense.share(of: me).lkr)"
        }
        let split = expense.splitMethod == .custom ? "Custom split" : "Split equally"
        return "Paid by \(expense.paidBy.name) • \(split)"
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        ExpensesView(viewModel: ExpensesViewModel(tripID: dependencies.previewTripID, store: dependencies.store))
    }
    .previewEnvironment(dependencies)
}

struct ExpenseAnalyticsView: View {
    @State private var viewModel: ExpenseAnalyticsViewModel
    @State private var mode = 0

    init(viewModel: ExpenseAnalyticsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        if viewModel.trip != nil {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SegmentedTabs(options: ["Categories", "Daily"], selection: $mode)

                    if mode == 0 {
                        categoryCard
                    }
                    SectionLabel("Daily Spent")
                    dailyCard

                    Text("Settle-up Suggestions")
                        .font(.title3.bold())
                        .padding(.top, 8)
                    if viewModel.settlements.isEmpty {
                        Label("Everyone is settled up.", systemImage: "checkmark.seal")
                            .foregroundStyle(.secondary)
                            .card()
                    }
                    ForEach(viewModel.settlements) { settlement in
                        settlementRow(settlement)
                    }

                    if !viewModel.payments.isEmpty {
                        SectionLabel("Payments made").padding(.top, 8)
                        VStack(spacing: 0) {
                            ForEach(viewModel.payments) { payment in
                                paymentRow(payment)
                                if payment.id != viewModel.payments.last?.id { Divider() }
                            }
                        }
                        .card(padding: 0)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Analytics")
        }
    }

    private var categoryCard: some View {
        HStack(spacing: 20) {
            Chart(ExpenseCategory.allCases) { category in
                SectorMark(
                    angle: .value("Amount", viewModel.spent(on: category)),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .foregroundStyle(category.color)
            }
            .frame(width: 140, height: 140)
            .overlay {
                VStack(spacing: 0) {
                    Text("TOTAL").font(.caption2).foregroundStyle(.secondary)
                    Text(viewModel.totalSpent.compact).font(.title3.bold())
                }
            }
            .accessibilityLabel("Total spent \(viewModel.totalSpent.lkr)")

            VStack(alignment: .leading, spacing: 10) {
                ForEach(ExpenseCategory.allCases) { category in
                    HStack {
                        Circle().fill(category.color).frame(width: 8, height: 8)
                        Text(category.rawValue).font(.subheadline.bold())
                        Spacer()
                        Text(viewModel.spent(on: category).lkr)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card(padding: 20)
    }

    private var dailyCard: some View {
        Chart(viewModel.dailyTotals) { total in
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

    private func settlementRow(_ settlement: Settlement) -> some View {
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
            Button("Settle") {
                withAnimation { viewModel.settle(settlement) }
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: false, height: 36))
            .accessibilityLabel("Mark \(settlement.from.name) paid \(settlement.to.name) \(settlement.amount.lkr)")
        }
        .card(padding: 14)
    }

    private func paymentRow(_ payment: Payment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(payment.from.name) paid \(payment.to.name)").font(.subheadline.bold())
                Text("\(payment.amount.lkr) • \(payment.date.text("d MMM HH:mm"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Undo") {
                withAnimation { viewModel.undo(payment) }
            }
            .font(.subheadline)
        }
        .padding(14)
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    NavigationStack {
        ExpenseAnalyticsView(viewModel: ExpenseAnalyticsViewModel(tripID: dependencies.previewTripID,
                                                                  store: dependencies.store, clock: dependencies.clock))
    }
    .previewEnvironment(dependencies)
}

// Has its own number pad that types into the total or a share
struct ExpenseFormView: View {
    @State private var viewModel: ExpenseFormViewModel
    @Environment(\.dismiss) private var dismiss

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", AmountInput.deleteKey]

    init(viewModel: ExpenseFormViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        amountDisplay

                        TextField("Tuk-tuk to Nine Arch Bridge", text: $viewModel.note)
                            .fieldStyle()

                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Category")
                            FlowLayout {
                                ForEach(ExpenseCategory.allCases) { item in
                                    Button { viewModel.category = item } label: { categoryChip(item) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Paid By")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(viewModel.members) { member in
                                        Button { viewModel.payerID = member.id } label: { payerChip(member) }
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
            .navigationTitle(viewModel.screenTitle)
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

    private var amountDisplay: some View {
        let isActive = viewModel.activeField == .total
        return Button {
            viewModel.activeField = .total
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("LKR").font(.title.bold()).foregroundStyle(.secondary)
                Text(viewModel.text(for: .total))
                    .font(.system(size: 56, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                // Only highlight when shares can be typed too
                if viewModel.splitMethod == .custom {
                    Capsule().fill(isActive ? Color.blue : .clear).frame(width: 60, height: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Amount \(viewModel.amount.lkr)")
    }

    private func categoryChip(_ item: ExpenseCategory) -> some View {
        let isSelected = viewModel.category == item
        return HStack(spacing: 6) {
            Circle()
                .fill(isSelected ? .white : item.color)
                .frame(width: 8, height: 8)
            Text(item.rawValue)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isSelected ? Color.blue : Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func payerChip(_ member: Member) -> some View {
        let isSelected = viewModel.payer?.id == member.id
        return HStack(spacing: 8) {
            AvatarView(member: member, size: 30)
            Text(member.name).font(.subheadline.weight(isSelected ? .semibold : .regular))
        }
        .padding(6)
        .padding(.trailing, 8)
        .background(isSelected ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isSelected ? Color.blue : .clear, lineWidth: 1.5))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Split With")
            SegmentedTabs(
                options: SplitMethod.allCases.map(\.rawValue),
                selection: Binding(
                    get: { SplitMethod.allCases.firstIndex(of: viewModel.splitMethod) ?? 0 },
                    set: { viewModel.setSplitMethod(SplitMethod.allCases[$0]) }
                )
            )

            switch viewModel.splitMethod {
            case .equal: equalSplit
            case .custom: customSplit
            }

            if let message = viewModel.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var equalSplit: some View {
        HStack(spacing: 12) {
            HStack(spacing: -10) {
                ForEach(viewModel.members) { member in
                    Button {
                        viewModel.toggleParticipant(member)
                    } label: {
                        AvatarView(member: member, size: 40)
                            .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
                            .opacity(viewModel.isIncluded(member) ? 1 : 0.3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(viewModel.isIncluded(member) ? "In the split" : "Left out")
                }
            }
            Text(viewModel.equalSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var customSplit: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                ForEach(viewModel.members) { member in
                    let field = ExpenseFormViewModel.Field.share(member.id)
                    let isActive = viewModel.activeField == field
                    Button {
                        viewModel.activeField = field
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(member: member, size: 30)
                            Text(member.name)
                            Spacer()
                            Text("LKR \(viewModel.text(for: field))")
                                .font(.headline)
                                .monospacedDigit()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isActive ? Color.blue.opacity(0.18) : Theme.fill,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(isActive ? Color.blue : .clear, lineWidth: 1.5))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(member.name)'s share")
                    .accessibilityValue(viewModel.shareAmount(for: member).lkr)
                    .accessibilityHint("Double tap, then type the amount on the number pad")
                    if member.id != viewModel.members.last?.id { Divider() }
                }
            }
            .card(padding: 0, fill: Theme.raised)

            Text(viewModel.customSummary)
                .font(.subheadline)
                .foregroundStyle(viewModel.unassigned == 0 ? .green : .secondary)
        }
    }

    private var keypad: some View {
        VStack(spacing: 10) {
            Button(viewModel.saveTitle) {
                if viewModel.save() { dismiss() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!viewModel.canSave)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    Button {
                        viewModel.press(key)
                    } label: {
                        Group {
                            if key == AmountInput.deleteKey {
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
                    .accessibilityLabel(key == AmountInput.deleteKey ? "Delete" : key)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .background(Theme.card)
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.amount)
    }
}

#Preview {
    let dependencies = AppDependencies.preview()
    Text("Expenses")
        .sheet(isPresented: .constant(true)) {
            ExpenseFormView(viewModel: ExpenseFormViewModel(tripID: dependencies.previewTripID,
                                                            store: dependencies.store, clock: dependencies.clock))
        }
        .previewEnvironment(dependencies)
}
