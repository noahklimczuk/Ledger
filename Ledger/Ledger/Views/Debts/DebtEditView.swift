import SwiftUI
import SwiftData

struct DebtEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let debt: Debt?
    var viewModel: DebtsViewModel? = nil

    @State private var name = ""
    @State private var kind: DebtKind = .creditCard
    @State private var balanceText = ""
    @State private var interestText = ""
    @State private var paymentText = ""
    @State private var notes = ""

    private var isEditing: Bool { debt != nil }
    private static let decimalLocale = Locale(identifier: "en_CA")

    private var balance: Decimal { Decimal(string: balanceText, locale: Self.decimalLocale) ?? 0 }
    private var interest: Double { Double(interestText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var payment: Decimal { Decimal(string: paymentText, locale: Self.decimalLocale) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Debt") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(DebtKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.sfSymbolName).tag(kind)
                        }
                    }
                }
                Section("Balance & Terms") {
                    LabeledContent("Balance Owed") {
                        TextField("0.00", text: $balanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Interest Rate (APR %)") {
                        TextField("0.0", text: $interestText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Monthly Payment") {
                        TextField("0.00", text: $paymentText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                payoffSection
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(isEditing ? "Edit Debt" : "New Debt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: populate)
        }
    }

    @ViewBuilder
    private var payoffSection: some View {
        if balance > 0 {
            Section("Projected Payoff") {
                if let projection = DebtPayoffCalculator.project(balance: balance, annualInterestRate: interest, monthlyPayment: payment) {
                    LabeledContent("Time to pay off", value: DebtPayoffCalculator.durationText(months: projection.months))
                    LabeledContent("Total interest", value: CurrencyFormatter.string(from: projection.totalInterest))
                } else {
                    Label("This payment won't cover the monthly interest — the balance won't go down. Increase the monthly payment.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func populate() {
        guard let debt else { return }
        name = debt.name
        kind = debt.kind
        balanceText = NSDecimalNumber(decimal: debt.currentBalance).stringValue
        interestText = debt.annualInterestRate == 0 ? "" : String(debt.annualInterestRate)
        paymentText = debt.minimumPayment == 0 ? "" : NSDecimalNumber(decimal: debt.minimumPayment).stringValue
        notes = debt.notes ?? ""
    }

    private func save() {
        let viewModel = viewModel ?? DebtsViewModel(modelContext: modelContext)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let debt {
            viewModel.updateDebt(debt, name: name, kind: kind, currentBalance: balance, annualInterestRate: interest, minimumPayment: payment, notes: trimmedNotes.isEmpty ? nil : trimmedNotes)
        } else {
            viewModel.addDebt(name: name, kind: kind, currentBalance: balance, annualInterestRate: interest, minimumPayment: payment, notes: trimmedNotes.isEmpty ? nil : trimmedNotes)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

#Preview {
    DebtEditView(debt: nil)
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
