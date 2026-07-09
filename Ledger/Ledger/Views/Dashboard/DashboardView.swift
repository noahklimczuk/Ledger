import Charts
import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @State private var viewModel: DashboardViewModel?

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
            }
            // Reload once a background refresh (sync + categorize) finishes, so balances and
            // recent transactions reflect the latest data without needing to re-open the tab.
            .onChange(of: refresh.refreshCount) { _, _ in viewModel?.load() }
            .refreshable { viewModel?.load() }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: DashboardViewModel) -> some View {
        if viewModel.accounts.isEmpty {
            EmptyStateView(
                systemImage: "banknote",
                title: "Welcome to Ledger",
                message: "Add your first account to start tracking balances and budgets."
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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

    private func balanceCard(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total Balance")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            Text(CurrencyFormatter.string(from: viewModel.totalBalance))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(LinearGradient.brand, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.brandTeal.opacity(0.35), radius: 10, y: 5)
    }

    // MARK: - This month: income / expenses / net

    private func monthSummaryCard(_ viewModel: DashboardViewModel) -> some View {
        HStack(spacing: 12) {
            summaryTile("Income", value: viewModel.monthIncome, color: .green)
            summaryTile("Expenses", value: viewModel.monthSpending, color: .red)
            summaryTile("Net", value: viewModel.monthNet, color: viewModel.monthNet < 0 ? .red : .primary)
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
                        y: .value("Amount", bar.amount.doubleValue)
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
                        y: .value("Category", slice.name)
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
                .frame(height: CGFloat(viewModel.topCategories.count) * 40 + 20)
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
