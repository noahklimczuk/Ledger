import SwiftUI
import SwiftData

struct BudgetListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: BudgetsViewModel?
    @State private var isPresentingNew = false
    @State private var editingRow: BudgetsViewModel.BudgetRow?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    VStack(spacing: 0) {
                        monthPicker(viewModel)
                        if viewModel.rows.isEmpty {
                            EmptyStateView(
                                systemImage: "chart.pie",
                                title: "No Budgets",
                                message: "Set a monthly budget for a category to start tracking progress.",
                                actionTitle: "Add Budget"
                            ) {
                                isPresentingNew = true
                            }
                        } else {
                            List {
                                ForEach(viewModel.rows) { row in
                                    Button { editingRow = row } label: {
                                        BudgetRowView(row: row)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            viewModel.delete(row)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .refreshable { viewModel.load() }
                        }
                    }
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $isPresentingNew, onDismiss: { viewModel?.load() }) {
                if let viewModel {
                    BudgetEditView(month: viewModel.selectedMonth, budgetRow: nil)
                }
            }
            .sheet(item: $editingRow, onDismiss: { viewModel?.load() }) { row in
                if let viewModel {
                    BudgetEditView(month: viewModel.selectedMonth, budgetRow: row)
                }
            }
            .task {
                if viewModel == nil { viewModel = BudgetsViewModel(modelContext: modelContext) }
                viewModel?.load()
            }
        }
    }

    private func monthPicker(_ viewModel: BudgetsViewModel) -> some View {
        HStack {
            Button {
                shiftMonth(viewModel, by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(DateFormatting.monthYear(viewModel.selectedMonth))
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(viewModel, by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding()
    }

    private func shiftMonth(_ viewModel: BudgetsViewModel, by value: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: value, to: viewModel.selectedMonth) {
            viewModel.selectedMonth = Budget.normalize(newMonth)
        }
    }
}

private struct BudgetRowView: View {
    let row: BudgetsViewModel.BudgetRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: row.budget.category?.sfSymbolName ?? "tag")
                    .foregroundStyle(row.budget.category.map { Color(hex: $0.colorHex) } ?? .gray)
                Text(row.budget.category?.name ?? "Uncategorized")
                    .fontWeight(.medium)
                Spacer()
                Text(CurrencyFormatter.string(from: row.spent))
                    .foregroundStyle(row.isOverBudget ? .red : .primary)
                Text("/ \(CurrencyFormatter.string(from: row.allocatedIncludingRollover))")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            BudgetProgressBar(progress: row.progress, isOverBudget: row.isOverBudget)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BudgetListView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
