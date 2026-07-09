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

    private let locale = Locale(identifier: "en_CA")

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Name", text: $name)
                }
                Section("Amounts") {
                    TextField("Target amount", text: $targetAmountText).keyboardType(.decimalPad)
                    TextField("Saved so far", text: $currentAmountText).keyboardType(.decimalPad)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || Decimal(string: targetAmountText, locale: locale) == nil)
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard let goal else { return }
        name = goal.name
        symbol = goal.sfSymbolName
        colorHex = goal.colorHex
        targetAmountText = NSDecimalNumber(decimal: goal.targetAmount).stringValue
        currentAmountText = NSDecimalNumber(decimal: goal.currentAmount).stringValue
        if let date = goal.targetDate {
            hasTargetDate = true
            targetDate = date
        }
    }

    private func save() {
        let target = Decimal(string: targetAmountText, locale: locale) ?? 0
        let current = Decimal(string: currentAmountText, locale: locale) ?? 0
        let date = hasTargetDate ? targetDate : nil

        let viewModel = SavingsGoalsViewModel(modelContext: modelContext)
        if let goal {
            viewModel.updateGoal(goal, name: name, sfSymbolName: symbol, colorHex: colorHex, targetAmount: target, currentAmount: current, targetDate: date)
        } else {
            viewModel.addGoal(name: name, sfSymbolName: symbol, colorHex: colorHex, targetAmount: target, currentAmount: current, targetDate: date)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
