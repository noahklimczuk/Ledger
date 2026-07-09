import SwiftUI
import SwiftData

struct BudgetEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let month: Date
    let budgetRow: BudgetsViewModel.BudgetRow?

    @State private var categories: [Category] = []
    @State private var category: Category?
    @State private var amountText = ""
    @State private var rolloverEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $category) {
                        Text("Select a category").tag(Category?.none)
                        ForEach(categories) { cat in
                            Text(cat.name).tag(Category?.some(cat))
                        }
                    }
                    .disabled(budgetRow != nil)
                }
                Section("Amount") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                    Toggle("Roll Over Unused Amount", isOn: $rolloverEnabled)
                }
            }
            .navigationTitle(budgetRow == nil ? "New Budget" : "Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(category == nil || Decimal(string: amountText, locale: Locale(identifier: "en_CA")) == nil)
                }
            }
            .task {
                categories = (try? modelContext.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.name)]))) ?? []
                if let budgetRow {
                    category = budgetRow.budget.category
                    amountText = NSDecimalNumber(decimal: budgetRow.budget.allocatedAmount).stringValue
                    rolloverEnabled = budgetRow.budget.rolloverEnabled
                }
            }
        }
    }

    private func save() {
        guard let category, let amount = Decimal(string: amountText, locale: Locale(identifier: "en_CA")) else { return }
        let viewModel = BudgetsViewModel(modelContext: modelContext)
        viewModel.selectedMonth = month
        viewModel.addOrUpdateBudget(category: category, allocatedAmount: amount, rolloverEnabled: rolloverEnabled)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
