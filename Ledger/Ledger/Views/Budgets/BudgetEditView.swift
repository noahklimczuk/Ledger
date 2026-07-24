import SwiftUI
import SwiftData

struct BudgetEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("budgetShowBiweekly") private var showBiweekly = false

    let month: Date
    let budgetRow: BudgetsViewModel.BudgetRow?
    /// Pre-picks the category (used by the off-plan spending quick-add), leaving just the amount.
    var preselectedCategory: Category? = nil

    @State private var categories: [Category] = []
    @State private var category: Category?
    @State private var amountText = ""
    @State private var rolloverEnabled = false
    @State private var isPresentingNewCategory = false
    /// Income minus everything already assigned this month (an edited budget's own allocation is
    /// handed back to the pool, since saving replaces it).
    @State private var leftToAssign: Decimal?

    /// Budgets track spending, so income categories stay out of the picker — but an existing
    /// budget that already points at one keeps its selection visible instead of showing blank.
    private var pickerCategories: [Category] {
        categories.filter { !$0.isIncome || $0.persistentModelID == category?.persistentModelID }
    }

    private func periodAmount(_ amount: Decimal) -> Decimal {
        showBiweekly ? amount / 2 : amount
    }

    private func periodMoney(_ amount: Decimal) -> String {
        CurrencyFormatter.string(from: periodAmount(amount))
    }

    private var periodSuffix: String {
        showBiweekly ? " /bi-weekly" : " /mo"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $category) {
                        Text("Select a category").tag(Category?.none)
                        ForEach(pickerCategories) { cat in
                            Text("\(cat.displayIcon)  \(cat.name)")
                                .tag(Category?.some(cat))
                        }
                    }
                    .disabled(budgetRow != nil)
                    if budgetRow == nil {
                        Button {
                            isPresentingNewCategory = true
                        } label: {
                            Label("New Category", systemImage: "plus.circle")
                        }
                    }
                }
                Section {
                    Picker("Budget period", selection: $showBiweekly) {
                        Text("Monthly").tag(false)
                        Text("Bi-weekly").tag(true)
                    }
                    .pickerStyle(.segmented)
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                    if let leftToAssign, leftToAssign > 0 {
                        Button {
                            amountText = NSDecimalNumber(decimal: periodAmount(leftToAssign)).stringValue
                        } label: {
                            Label("Assign Remaining (\(periodMoney(leftToAssign))\(periodSuffix))", systemImage: "arrow.down.to.line")
                        }
                    }
                    Toggle("Roll Over Unused Amount", isOn: $rolloverEnabled)
                } header: {
                    Text("Amount")
                }
            }
            .navigationTitle(budgetRow == nil ? "New Budget" : "Edit Budget")
            .accent(.budgets)
            .accentWash(.budgets)
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(category == nil || ImportValueParsing.decimal(from: amountText) == nil)
                }
            }
            .sheet(isPresented: $isPresentingNewCategory, onDismiss: selectNewlyAddedCategory) {
                CategoryDetailEditView(
                    category: nil,
                    parentCandidates: categories.filter { $0.parent == nil }
                )
            }
            .task {
                loadCategories()
                if let budgetRow {
                    category = budgetRow.budget.category
                    amountText = NSDecimalNumber(decimal: periodAmount(budgetRow.budget.allocatedAmount)).stringValue
                    rolloverEnabled = budgetRow.budget.rolloverEnabled
                } else if let preselectedCategory {
                    category = preselectedCategory
                }
                computeLeftToAssign()
            }
            .onChange(of: showBiweekly) { _, newValue in
                guard let current = ImportValueParsing.decimal(from: amountText) else { return }
                let converted = newValue ? current / 2 : current * 2
                amountText = NSDecimalNumber(decimal: converted).stringValue
            }
        }
    }

    private func loadCategories() {
        categories = (try? modelContext.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    private func computeLeftToAssign() {
        let viewModel = BudgetsViewModel(modelContext: modelContext)
        viewModel.selectedMonth = month
        leftToAssign = viewModel.leftToAssign + (budgetRow?.budget.allocatedAmount ?? 0)
    }

    /// After the New Category sheet closes, pick out whatever it added (a cancelled sheet adds
    /// nothing) and select it so the budget is ready to save without re-opening the picker.
    private func selectNewlyAddedCategory() {
        let known = Set(categories.map(\.persistentModelID))
        loadCategories()
        if let added = categories.first(where: { !known.contains($0.persistentModelID) && !$0.isIncome }) {
            category = added
        }
    }

    private func save() {
        guard let category, let amount = ImportValueParsing.decimal(from: amountText) else { return }
        let monthlyAmount = showBiweekly ? amount * 2 : amount
        let viewModel = BudgetsViewModel(modelContext: modelContext)
        viewModel.selectedMonth = month
        viewModel.addOrUpdateBudget(category: category, allocatedAmount: monthlyAmount, rolloverEnabled: rolloverEnabled)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
