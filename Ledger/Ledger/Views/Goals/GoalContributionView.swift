import SwiftUI
import SwiftData

/// The "add money" sheet for a savings goal: a big amount field, quick-add chips, a one-tap
/// "finish the goal" shortcut, and a live preview of where the contribution lands you.
struct GoalContributionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let goal: SavingsGoal

    @State private var amountText = ""
    @FocusState private var amountFocused: Bool

    private let quickAmounts: [Decimal] = [25, 50, 100, 250]

    private var amount: Decimal? {
        guard let value = ImportValueParsing.decimal(from: amountText.trimmingCharacters(in: .whitespaces)),
              value > 0 else { return nil }
        return value
    }

    private var projectedTotal: Decimal { goal.savedAmount + (amount ?? 0) }

    private var projectedPercent: Int {
        guard goal.targetAmount > 0 else { return 0 }
        let value = (projectedTotal as NSDecimalNumber).doubleValue / (goal.targetAmount as NSDecimalNumber).doubleValue
        return Int(min(max(value, 0), 1) * 100)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 8)

                    quickChips

                    if goal.remaining > 0 {
                        Button {
                            amountText = NSDecimalNumber(decimal: goal.remaining).stringValue
                        } label: {
                            Label("Finish the Goal (\(CurrencyFormatter.string(from: goal.remaining)))", systemImage: "flag.checkered")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(hex: goal.colorHex))
                    }

                    if amount != nil {
                        Text("Brings you to \(CurrencyFormatter.string(from: projectedTotal)) · \(projectedPercent)% of the goal")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                .padding()
            }
            .navigationTitle("Add Money")
            .accent(.goals)
            .accentWash(.goals)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(amount == nil)
                }
            }
            .onAppear { amountFocused = true }
        }
        .presentationDetents([.medium])
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: goal.sfSymbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color(hex: goal.colorHex), in: Circle())
            Text(goal.name)
                .font(.headline)
            Text("\(CurrencyFormatter.string(from: goal.savedAmount)) of \(CurrencyFormatter.string(from: goal.targetAmount)) · \(CurrencyFormatter.string(from: goal.remaining)) to go")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: goal.progress)
                .tint(Color(hex: goal.colorHex))
        }
    }

    private var quickChips: some View {
        HStack(spacing: 10) {
            ForEach(quickAmounts, id: \.self) { chip in
                Button {
                    // Chips stack onto whatever's typed, so $100 + $25 + $25 is three taps.
                    let current = ImportValueParsing.decimal(from: amountText.trimmingCharacters(in: .whitespaces)) ?? 0
                    amountText = NSDecimalNumber(decimal: current + chip).stringValue
                } label: {
                    Text("+\(CurrencyFormatter.string(from: chip))")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func add() {
        guard let amount else { return }
        SavingsGoalsViewModel(modelContext: modelContext).addContribution(amount, to: goal)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
