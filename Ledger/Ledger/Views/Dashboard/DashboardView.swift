import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
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
            Text("This Month")
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

#Preview {
    DashboardView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
