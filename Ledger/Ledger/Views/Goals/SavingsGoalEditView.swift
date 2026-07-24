import SwiftUI
import SwiftData

struct SavingsGoalEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let goal: SavingsGoal?

    @State private var name = ""
    @State private var symbol = "target"
    @State private var colorHex = "#34C759"
    @State private var targetAmountText = ""
    @State private var currentAmountText = ""
    @State private var hasTargetDate = false
    @State private var targetDate = Date()
    @State private var trackedAccount: Account?
    @State private var accounts: [Account] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Name", text: $name)
                }
                Section {
                    Picker("Tracked From", selection: $trackedAccount) {
                        Text("Manual contributions").tag(Account?.none)
                        ForEach(accounts) { account in
                            Text("\(account.displayIcon)  \(account.name)")
                                .tag(Account?.some(account))
                        }
                    }
                    if let trackedAccount {
                        LabeledContent("Current balance", value: CurrencyFormatter.string(from: max(trackedAccount.currentBalance, 0)))
                    }
                } header: {
                    Text("Progress Source")
                }
                Section("Amounts") {
                    TextField("Target amount", text: $targetAmountText).keyboardType(.decimalPad)
                    if trackedAccount == nil {
                        TextField("Saved so far", text: $currentAmountText).keyboardType(.decimalPad)
                    }
                }
                Section("Target Date") {
                    Toggle("Set a target date", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("By", selection: $targetDate, in: Date()..., displayedComponents: .date)
                    }
                }
                Section("Icon") {
                    IconPickerView(selection: $symbol)
                }
                Section("Color") {
                    ColorPickerGridView(selectionHex: $colorHex)
                }
            }
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
            .accent(.goals)
            .accentWash(.goals)
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || ImportValueParsing.decimal(from: targetAmountText) == nil)
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        accounts = (try? modelContext.fetch(descriptor)) ?? []

        guard let goal else { return }
        name = goal.name
        symbol = goal.sfSymbolName
        colorHex = goal.colorHex
        targetAmountText = NSDecimalNumber(decimal: goal.targetAmount).stringValue
        currentAmountText = NSDecimalNumber(decimal: goal.currentAmount).stringValue
        trackedAccount = goal.account
        if let date = goal.targetDate {
            hasTargetDate = true
            targetDate = date
        }
    }

    private func save() {
        let target = ImportValueParsing.decimal(from: targetAmountText) ?? 0
        let current = ImportValueParsing.decimal(from: currentAmountText) ?? 0
        let date = hasTargetDate ? targetDate : nil

        let viewModel = SavingsGoalsViewModel(modelContext: modelContext)
        if let goal {
            viewModel.updateGoal(goal, name: name, sfSymbolName: symbol, colorHex: colorHex, targetAmount: target, currentAmount: current, targetDate: date, account: trackedAccount)
        } else {
            viewModel.addGoal(name: name, sfSymbolName: symbol, colorHex: colorHex, targetAmount: target, currentAmount: current, targetDate: date, account: trackedAccount)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
