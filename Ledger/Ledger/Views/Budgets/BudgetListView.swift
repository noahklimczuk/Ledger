import SwiftUI
import SwiftData

struct BudgetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @State private var viewModel: BudgetsViewModel?
    @State private var isPresentingNew = false
    @State private var editingRow: BudgetsViewModel.BudgetRow?
    @State private var isConfirmingAutoGenerate = false
    @State private var autoGenerateResult: String?

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
                                    budgetRow(row, month: viewModel.selectedMonth)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                viewModel.delete(row)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                editingRow = row
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(.accentColor)
                                        }
                                        // Long-press menu, so editing/deleting a budget stays reachable
                                        // even where the paged tab swipe competes with row swipes.
                                        .contextMenu {
                                            Button {
                                                editingRow = row
                                            } label: {
                                                Label("Edit Budget", systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                viewModel.delete(row)
                                            } label: {
                                                Label("Delete Budget", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            // Pull-to-refresh runs a real sync; the refreshCount observer below
                            // then reloads the rows with the new spent amounts.
                            .refreshable { await refresh.refresh(container: modelContext.container) }
                        }
                    }
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { isPresentingNew = true } label: {
                            Label("Add Budget", systemImage: "plus")
                        }
                        Button { isConfirmingAutoGenerate = true } label: {
                            Label("Auto-Generate from Last 3 Months", systemImage: "wand.and.stars")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .confirmationDialog(
                "Create budgets for \(DateFormatting.monthYear(viewModel?.selectedMonth ?? .now)) from your average spending over the last 3 months?",
                isPresented: $isConfirmingAutoGenerate,
                titleVisibility: .visible
            ) {
                Button("Auto-Generate") {
                    let created = viewModel?.generateFromRecentHistory() ?? 0
                    autoGenerateResult = created > 0
                        ? "Set \(created) budget\(created == 1 ? "" : "s") from recent spending."
                        : "No spending found in the last 3 months to build a budget from."
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Existing budgets for this month will be updated to match.")
            }
            .alert("Budget", isPresented: Binding(get: { autoGenerateResult != nil }, set: { if !$0 { autoGenerateResult = nil } })) {
                Button("OK", role: .cancel) { autoGenerateResult = nil }
            } message: {
                Text(autoGenerateResult ?? "")
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
            // Reload once a background refresh (sync + categorize) finishes, so spent amounts
            // reflect freshly imported transactions without re-opening the tab.
            .onChange(of: refresh.refreshCount) { _, _ in viewModel?.load() }
        }
    }

    @ViewBuilder
    private func budgetRow(_ row: BudgetsViewModel.BudgetRow, month: Date) -> some View {
        if let category = row.budget.category {
            NavigationLink {
                CategoryTransactionsView(category: category, month: month)
            } label: {
                BudgetRowView(row: row)
            }
        } else {
            BudgetRowView(row: row)
        }
    }

    private func monthPicker(_ viewModel: BudgetsViewModel) -> some View {
        HStack {
            monthChevron("chevron.left") { shiftMonth(viewModel, by: -1) }
            Spacer()
            Text(DateFormatting.monthYear(viewModel.selectedMonth))
                .font(.headline)
            Spacer()
            monthChevron("chevron.right") { shiftMonth(viewModel, by: 1) }
        }
        .padding(.horizontal)
    }

    /// A 44pt hit area — the bare chevron glyph is far too small a tap target on its own.
    private func monthChevron(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
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
                // A long category name truncates instead of wrapping and pushing the
                // amounts onto a second line.
                Text(row.budget.category?.name ?? "Uncategorized")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(CurrencyFormatter.string(from: row.spent))
                    .foregroundStyle(row.isOverBudget ? Color.red : Color.primary)
                    .layoutPriority(1)
                Text("/ \(CurrencyFormatter.string(from: row.allocatedIncludingRollover))")
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
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
        .environment(AppRefreshCoordinator())
}
