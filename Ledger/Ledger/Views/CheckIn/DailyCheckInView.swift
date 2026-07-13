import SwiftUI
import SwiftData

/// The 2-minute daily ritual, as a guided five-step flow: catch up on unreviewed transactions,
/// see which budgets drifted, confirm upcoming bills, re-zero the plan, done. Every step has an
/// "all clear" state so the ritual is quick when the day was clean.
struct DailyCheckInView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: DailyCheckInViewModel?
    @State private var step = 0
    @State private var dailyReminderOn = false
    /// The transaction whose detail popup is open, if any. Tapping a review row sets this.
    @State private var selectedTransaction: Transaction?

    private let stepCount = 5

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    VStack(spacing: 0) {
                        progressDots
                        ScrollView {
                            stepContent(viewModel)
                                .padding()
                                // Each step is its own identity, so advancing slides the old step
                                // out and the new one in (and resets the scroll to the top).
                                .id(step)
                                .transition(.push(from: .trailing))
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        continueButton(viewModel)
                    }
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Daily Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .task {
                dailyReminderOn = DailyCheckInViewModel.dailyReminderEnabled
                if viewModel == nil {
                    let model = DailyCheckInViewModel(modelContext: modelContext)
                    model.load()
                    viewModel = model
                }
            }
            // Tapping a review row opens that exact transaction in a popup, so its category and
            // details can be edited without leaving the check-in.
            .sheet(item: $selectedTransaction) { transaction in
                NavigationStack {
                    TransactionDetailView(transaction: transaction)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { selectedTransaction = nil }
                            }
                        }
                }
            }
        }
        .interactiveDismissDisabled(step > 0 && step < stepCount - 1)
    }

    // MARK: - Chrome

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Color.accentColor : Color(.systemGray4))
                    .frame(width: index == step ? 22 : 8, height: 8)
            }
        }
        .padding(.vertical, 12)
        .animation(.spring(duration: 0.3), value: step)
    }

    private func continueButton(_ viewModel: DailyCheckInViewModel) -> some View {
        Button {
            if step < stepCount - 1 {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(duration: 0.3)) { step += 1 }
            } else {
                let reminder = dailyReminderOn
                Task {
                    await viewModel.complete(dailyReminder: reminder)
                    dismiss()
                }
            }
        } label: {
            Text(step < stepCount - 1 ? "Continue" : "Done for Today")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding()
        .background(.bar)
    }

    // MARK: - Steps

    @ViewBuilder
    private func stepContent(_ viewModel: DailyCheckInViewModel) -> some View {
        switch step {
        case 0: reviewStep(viewModel)
        case 1: budgetsStep(viewModel)
        case 2: billsStep(viewModel)
        case 3: planStep(viewModel)
        default: doneStep(viewModel)
        }
    }

    private func reviewStep(_ viewModel: DailyCheckInViewModel) -> some View {
        VStack(spacing: 16) {
            stepHeader(
                symbol: "checkmark.circle",
                title: "Catch Up on Transactions",
                subtitle: "A quick skim keeps surprises from hiding in the feed."
            )
            if viewModel.unreviewed.isEmpty {
                allClear("All caught up", detail: "No transactions waiting for review.")
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.unreviewed) { transaction in
                        reviewRow(transaction, viewModel: viewModel)
                        if transaction.persistentModelID != viewModel.unreviewed.last?.persistentModelID {
                            Divider().padding(.leading)
                        }
                    }
                }
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                Button {
                    withAnimation { viewModel.markAllReviewed() }
                } label: {
                    Label("Mark All Reviewed", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func reviewRow(_ transaction: Transaction, viewModel: DailyCheckInViewModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Tapping the merchant opens the full transaction popup. The category menu below
                // stays its own control so the quick-set dropdown still works.
                Button { selectedTransaction = transaction } label: {
                    Text(transaction.merchant)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack(spacing: 6) {
                    Text(DateFormatting.relativeDay(transaction.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    categoryMenu(transaction, viewModel: viewModel)
                }
            }
            Spacer(minLength: 8)
            Button { selectedTransaction = transaction } label: {
                Text(CurrencyFormatter.string(from: transaction.amount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(transaction.amount < 0 ? Color.primary : Color.green)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                withAnimation { viewModel.markReviewed(transaction) }
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    /// A little dropdown to set (or clear) the transaction's category right in the review step.
    private func categoryMenu(_ transaction: Transaction, viewModel: DailyCheckInViewModel) -> some View {
        Menu {
            Button {
                viewModel.setCategory(nil, for: transaction)
            } label: {
                Label("Uncategorized", systemImage: "tag.slash")
            }
            if !viewModel.expenseCategories.isEmpty {
                Section("Expenses") {
                    ForEach(viewModel.expenseCategories) { category in
                        categoryOption(category, transaction, viewModel)
                    }
                }
            }
            if !viewModel.incomeCategories.isEmpty {
                Section("Income") {
                    ForEach(viewModel.incomeCategories) { category in
                        categoryOption(category, transaction, viewModel)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(transaction.category.map { Color(hex: $0.colorHex) } ?? Color(.systemGray3))
                    .frame(width: 7, height: 7)
                Text(transaction.category?.name ?? "Set category")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(transaction.category == nil ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.systemGray6), in: Capsule())
        }
    }

    private func categoryOption(_ category: Category, _ transaction: Transaction, _ viewModel: DailyCheckInViewModel) -> some View {
        Button {
            viewModel.setCategory(category, for: transaction)
        } label: {
            Label(category.name, systemImage: category.sfSymbolName)
        }
    }

    private func budgetsStep(_ viewModel: DailyCheckInViewModel) -> some View {
        VStack(spacing: 16) {
            stepHeader(
                symbol: "chart.pie",
                title: "How the Plan Held Up",
                subtitle: "Catch drift now, while there's still month left to fix it."
            )
            if viewModel.overBudget.isEmpty && viewModel.aheadOfPace.isEmpty {
                allClear("On plan", detail: "No budgets are over or running ahead of pace.")
            } else {
                if !viewModel.overBudget.isEmpty {
                    budgetIssueCard(
                        title: "Over budget",
                        rows: viewModel.overBudget,
                        color: .red
                    ) { row in
                        "\(CurrencyFormatter.string(from: -row.remaining)) over"
                    }
                }
                if !viewModel.aheadOfPace.isEmpty {
                    budgetIssueCard(
                        title: "Ahead of pace",
                        rows: viewModel.aheadOfPace,
                        color: .orange
                    ) { row in
                        "\(row.percentUsed.map { "\($0)%" } ?? "—") used · \(Int(viewModel.monthProgress * 100))% of month gone"
                    }
                }
            }
        }
    }

    private func budgetIssueCard(
        title: String,
        rows: [BudgetsViewModel.BudgetRow],
        color: Color,
        detail: @escaping (BudgetsViewModel.BudgetRow) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.budget.category?.sfSymbolName ?? "tag")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(row.budget.category.map { Color(hex: $0.colorHex) } ?? .gray, in: Circle())
                    Text(row.budget.category?.name ?? "Uncategorized")
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(detail(row))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func billsStep(_ viewModel: DailyCheckInViewModel) -> some View {
        VStack(spacing: 16) {
            stepHeader(
                symbol: "calendar.badge.clock",
                title: "Money Already Spoken For",
                subtitle: "Bills due in the next two weeks — this money isn't spendable."
            )
            if viewModel.upcomingBills.isEmpty {
                allClear("Nothing due soon", detail: "No bill reminders in the next 14 days.")
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.upcomingBills) { bill in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bill.name)
                                    .font(.subheadline.weight(.medium))
                                Text(bill.isOverdue ? "Overdue · was due \(DateFormatting.medium(bill.dueDate))" : "Due \(DateFormatting.relativeDay(bill.dueDate))")
                                    .font(.caption)
                                    .foregroundStyle(bill.isOverdue ? Color.red : Color.secondary)
                            }
                            Spacer()
                            Text(CurrencyFormatter.string(from: bill.amount))
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        if bill.persistentModelID != viewModel.upcomingBills.last?.persistentModelID {
                            Divider().padding(.leading)
                        }
                    }
                    Divider()
                    HStack {
                        Text("Total")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(CurrencyFormatter.string(from: viewModel.upcomingBillsTotal))
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func planStep(_ viewModel: DailyCheckInViewModel) -> some View {
        VStack(spacing: 16) {
            stepHeader(
                symbol: "equal.circle",
                title: "Zero Out the Plan",
                subtitle: "The week's deposits and spending may have moved Left to Assign."
            )
            VStack(spacing: 8) {
                Text("Left to Assign")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.string(from: viewModel.leftToAssign))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(planColor(viewModel))
                Text(planMessage(viewModel))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func planColor(_ viewModel: DailyCheckInViewModel) -> Color {
        if viewModel.leftToAssign < 0 { return .red }
        if viewModel.leftToAssign == 0 && viewModel.incomeToAssign > 0 { return .brandEmerald }
        return .primary
    }

    private func planMessage(_ viewModel: DailyCheckInViewModel) -> String {
        if viewModel.incomeToAssign <= 0 && viewModel.leftToAssign == 0 {
            return "Set your income on the Budgets tab to start the plan."
        }
        if viewModel.leftToAssign < 0 {
            return "The plan is over-assigned. Trim a budget on the Budgets tab to bring it back to zero."
        }
        if viewModel.leftToAssign == 0 {
            return "Every dollar has a job. Nothing to do here."
        }
        return "Head to the Budgets tab and give this money a job — savings count too."
    }

    private func doneStep(_ viewModel: DailyCheckInViewModel) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(LinearGradient.brand)
                .padding(.top, 12)
            Text("You're Set for Today")
                .font(.title2.bold())
            HStack(spacing: 12) {
                doneTile(value: "\(viewModel.reviewedThisSession)", label: "reviewed")
                doneTile(value: "\(viewModel.overBudget.count)", label: "over budget")
                doneTile(value: CurrencyFormatter.string(from: viewModel.upcomingBillsTotal), label: "bills ahead")
            }
            Toggle(isOn: $dailyReminderOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remind me daily")
                        .font(.subheadline.weight(.medium))
                    Text("Every night at 10 PM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func doneTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Shared pieces

    private func stepHeader(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private func allClear(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.brandEmerald)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    DailyCheckInView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
