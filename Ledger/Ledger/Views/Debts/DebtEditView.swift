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
    @State private var isConfirmingPaidOff = false

    private var isEditing: Bool { debt != nil }

    private var balance: Decimal { ImportValueParsing.decimal(from: balanceText) ?? 0 }
    private var interest: Double { Double(interestText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var payment: Decimal { ImportValueParsing.decimal(from: paymentText) ?? 0 }

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
                assignedTransactionsSection
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
                paidOffSection
            }
            .navigationTitle(isEditing ? "Edit Debt" : "New Debt")
            .accent(.debt)
            .accentWash(.debt)
            .scrollContentBackground(.hidden)
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
            .confirmationDialog("Mark this debt as paid off?", isPresented: $isConfirmingPaidOff, titleVisibility: .visible) {
                Button("Mark as Paid Off") { markPaidOff() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This zeroes the balance and removes it from your debt tracker. 🎉")
            }
            .onAppear(perform: populate)
        }
    }

    /// A one-tap "I've cleared this" action for an existing debt: archives it out of the tracker
    /// rather than making the user manually zero the balance. New debts have nothing to pay off yet.
    @ViewBuilder
    private var paidOffSection: some View {
        if isEditing {
            Section {
                Button {
                    isConfirmingPaidOff = true
                } label: {
                    Label("Mark as Paid Off", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(Palette.income)
            }
        }
    }

    /// The transactions assigned to this debt, newest first. Read-only here — the link is made from
    /// the transaction editor or automatically — but it makes the assignments (and which ones moved
    /// the balance) visible from the debt itself.
    @ViewBuilder
    private var assignedTransactionsSection: some View {
        if let debt, !debt.transactions.isEmpty {
            Section {
                ForEach(debt.transactions.sorted { $0.date > $1.date }) { transaction in
                    TransactionRowView(transaction: transaction)
                }
            } header: {
                Text("Assigned Transactions")
            }
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
                        .font(.appFootnote)
                        .foregroundStyle(Palette.amber)
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

    private func markPaidOff() {
        guard let debt else { return }
        let viewModel = viewModel ?? DebtsViewModel(modelContext: modelContext)
        viewModel.markPaidOff(debt)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
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
