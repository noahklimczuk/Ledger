import Charts
import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @State private var viewModel: DashboardViewModel?
    @State private var isPresentingCheckIn = false
    @State private var isCheckInDue = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Dashboard")
            .task {
                if viewModel == nil { viewModel = DashboardViewModel(modelContext: modelContext) }
                viewModel?.load()
                isCheckInDue = DailyCheckInViewModel.isDue()
            }
            .sheet(isPresented: $isPresentingCheckIn, onDismiss: {
                isCheckInDue = DailyCheckInViewModel.isDue()
                viewModel?.load()
            }) {
                DailyCheckInView()
            }
            // Reload once a background refresh (sync + categorize) finishes, so balances and
            // recent transactions reflect the latest data without needing to re-open the tab.
            .onChange(of: refresh.refreshCount) { _, _ in viewModel?.load() }
            // Pull-to-refresh runs a real sync; the refreshCount bump above then reloads the VM.
            .refreshable { await refresh.refresh(container: modelContext.container) }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: DashboardViewModel) -> some View {
        if viewModel.accounts.isEmpty {
            onboardingCard
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isCheckInDue {
                        checkInCard
                    }
                    balanceCard(viewModel)
                    monthSummaryCard(viewModel)
                    incomeExpenseChartCard(viewModel)
                    categoryChartCard(viewModel)
                    safeToSpendCard(viewModel)
                    budgetCard(viewModel)
                    recentTransactionsSection(viewModel)
                }
                .padding()
            }
        }
    }

    /// First-run guidance: a blank dashboard should say what to do, not just that it's empty.
    private var onboardingCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(LinearGradient.brand)
                    Text("Welcome to Ledger")
                        .font(.title2.bold())
                    Text("Three ways to get your money in — pick whichever fits.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

                onboardingStep(
                    number: 1,
                    symbol: "banknote",
                    title: "Add an account",
                    detail: "Accounts tab → +. A chequing account with a starting balance is enough to begin."
                )
                onboardingStep(
                    number: 2,
                    symbol: "link",
                    title: "Or connect Wealthsimple",
                    detail: "More → Connect Wealthsimple signs in with your Wealthsimple login and pulls in your Cash account and transactions automatically."
                )
                onboardingStep(
                    number: 3,
                    symbol: "square.and.arrow.down",
                    title: "Or import a file",
                    detail: "More → Import CSV / OFX brings in a statement export from any bank, with automatic deduplication."
                )

                Text("Once transactions are in, Ledger auto-categorizes them, spots recurring bills, and can suggest a monthly budget from your real spending.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding()
        }
    }

    private func onboardingStep(number: Int, symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(LinearGradient.brand, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    /// Shown on days the check-in hasn't been done yet — the ritual only sticks if the app
    /// does the remembering.
    private var checkInCard: some View {
        Button {
            isPresentingCheckIn = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(LinearGradient.brand, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Check-In")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text("2 minutes to review today and keep the plan at zero")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func balanceCard(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total Balance")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            Text(CurrencyFormatter.string(from: viewModel.totalBalance))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(LinearGradient.brand, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.brandTeal.opacity(0.35), radius: 10, y: 5)
    }

    // MARK: - This month: income / expenses / net

    private func monthSummaryCard(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This Month · \(DateFormatting.monthYear(.now))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                summaryTile("Income", value: viewModel.monthIncome, color: .green)
                summaryTile("Expenses", value: viewModel.monthSpending, color: .red)
                summaryTile("Net", value: viewModel.monthNet, color: viewModel.monthNet < 0 ? .red : .primary)
            }
        }
    }

    private func summaryTile(_ label: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(CurrencyFormatter.string(from: value))
                .font(.headline)
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func incomeExpenseChartCard(_ viewModel: DashboardViewModel) -> some View {
        if viewModel.monthIncome > 0 || viewModel.monthSpending > 0 {
            let bars = [
                FlowBar(label: "Income", amount: viewModel.monthIncome, color: .green),
                FlowBar(label: "Expenses", amount: viewModel.monthSpending, color: .red),
            ]
            card(title: "Income vs. Expenses") {
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Type", bar.label),
                        y: .value("Amount", bar.amount.doubleValue),
                        width: .fixed(44)
                    )
                    .foregroundStyle(bar.color)
                    .annotation(position: .top) {
                        Text(CurrencyFormatter.string(from: bar.amount))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .cornerRadius(6)
                }
                .chartYAxis(.hidden)
                .frame(height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Income versus expenses this month")
                .accessibilityValue("Income \(CurrencyFormatter.string(from: viewModel.monthIncome)), expenses \(CurrencyFormatter.string(from: viewModel.monthSpending))")
            }
        }
    }

    @ViewBuilder
    private func categoryChartCard(_ viewModel: DashboardViewModel) -> some View {
        if !viewModel.topCategories.isEmpty {
            card(title: "Top Spending Categories") {
                Chart(viewModel.topCategories) { slice in
                    BarMark(
                        x: .value("Amount", slice.amount.doubleValue),
                        y: .value("Category", slice.name),
                        height: .fixed(16)
                    )
                    .foregroundStyle(Color(hex: slice.colorHex))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(CurrencyFormatter.string(from: slice.amount))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .cornerRadius(4)
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(viewModel.topCategories.count) * 38 + 20)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Top spending categories")
                .accessibilityValue(
                    viewModel.topCategories
                        .map { "\($0.name) \(CurrencyFormatter.string(from: $0.amount))" }
                        .joined(separator: ", ")
                )
            }
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func safeToSpendCard(_ viewModel: DashboardViewModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Safe to Spend")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.string(from: viewModel.safeToSpend))
                    .font(.title2.bold())
                    .foregroundStyle(viewModel.safeToSpend < 0 ? Color.red : Color.primary)
                if viewModel.reservedForBills > 0 {
                    Text("After reserving \(CurrencyFormatter.string(from: viewModel.reservedForBills)) for upcoming bills")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: viewModel.safeToSpend < 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(viewModel.safeToSpend < 0 ? .red : .green)
                .font(.title)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func budgetCard(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spending vs Budget")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text(CurrencyFormatter.string(from: viewModel.monthSpending))
                    .font(.title3.bold())
                Text("of \(CurrencyFormatter.string(from: viewModel.monthBudgetTotal)) budgeted")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if viewModel.monthBudgetTotal > 0 {
                let spent = (viewModel.monthSpending as NSDecimalNumber).doubleValue
                let budgeted = (viewModel.monthBudgetTotal as NSDecimalNumber).doubleValue
                let progress = min(max(spent / budgeted, 0), 1)
                ProgressView(value: progress)
                    .tint(progress >= 1 ? .red : .accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func recentTransactionsSection(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Transactions")
                .font(.headline)
            if viewModel.recentTransactions.isEmpty {
                Text("No transactions yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.recentTransactions) { transaction in
                        TransactionRowView(transaction: transaction)
                            .padding(.horizontal)
                        if transaction.persistentModelID != viewModel.recentTransactions.last?.persistentModelID {
                            Divider().padding(.leading)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

private struct FlowBar: Identifiable {
    var id: String { label }
    let label: String
    let amount: Decimal
    let color: Color
}

private extension Decimal {
    var doubleValue: Double { (self as NSDecimalNumber).doubleValue }
}

#Preview {
    DashboardView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
        .environment(AppRefreshCoordinator())
}
