import SwiftUI

/// Sets the month's planned income — the pot the zero-based plan assigns from. Defaults to the
/// income actually received this month; people who budget ahead of payday can override it.
struct BudgetIncomeEditView: View {
    @Environment(\.dismiss) private var dismiss

    let month: Date
    let actualIncome: Decimal
    let currentOverride: Decimal?
    let onSave: (Decimal?) -> Void

    @State private var amountText: String

    init(month: Date, actualIncome: Decimal, currentOverride: Decimal?, onSave: @escaping (Decimal?) -> Void) {
        self.month = month
        self.actualIncome = actualIncome
        self.currentOverride = currentOverride
        self.onSave = onSave
        let initial = currentOverride ?? actualIncome
        _amountText = State(initialValue: initial > 0 ? NSDecimalNumber(decimal: initial).stringValue : "")
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.trimmingCharacters(in: .whitespaces), locale: Locale(identifier: "en_CA"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                } header: {
                    Text("Planned Income · \(DateFormatting.monthYear(month))")
                } footer: {
                    Text("This is the pot your budget assigns from. Give every dollar of it a category and Left to Assign hits zero — that's the whole plan.")
                }

                Section {
                    Button {
                        onSave(nil)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use Actual Income")
                            Text("\(CurrencyFormatter.string(from: actualIncome)) received so far this month")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Tracks deposits automatically as they arrive.")
                }
            }
            .navigationTitle("Monthly Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(parsedAmount)
                        dismiss()
                    }
                    .disabled(parsedAmount == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
