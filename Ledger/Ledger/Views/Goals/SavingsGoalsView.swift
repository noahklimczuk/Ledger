import SwiftUI
import SwiftData

struct SavingsGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SavingsGoalsViewModel?
    @State private var isPresentingNew = false
    @State private var editingGoal: SavingsGoal?
    @State private var contributingGoal: SavingsGoal?
    @State private var contributionText = ""

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.goals.isEmpty {
                    EmptyStateView(
                        systemImage: "target",
                        title: "No Savings Goals",
                        message: "Set a goal with a target amount and date to track your progress.",
                        actionTitle: "Add Goal"
                    ) {
                        isPresentingNew = true
                    }
                } else {
                    List {
                        ForEach(viewModel.goals) { goal in
                            GoalCard(goal: goal)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        viewModel.delete(goal)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        editingGoal = goal
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        contributionText = ""
                                        contributingGoal = goal
                                    } label: {
                                        Label("Add", systemImage: "plus")
                                    }
                                    .tint(.green)
                                }
                        }
                    }
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Savings Goals")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $isPresentingNew, onDismiss: { viewModel?.load() }) {
            SavingsGoalEditView(goal: nil)
        }
        .sheet(item: $editingGoal, onDismiss: { viewModel?.load() }) { goal in
            SavingsGoalEditView(goal: goal)
        }
        .alert("Add Contribution", isPresented: Binding(get: { contributingGoal != nil }, set: { if !$0 { contributingGoal = nil } })) {
            TextField("Amount", text: $contributionText)
                .keyboardType(.decimalPad)
            Button("Add") {
                if let goal = contributingGoal, let amount = Decimal(string: contributionText, locale: Locale(identifier: "en_CA")) {
                    viewModel?.addContribution(amount, to: goal)
                }
                contributingGoal = nil
            }
            Button("Cancel", role: .cancel) { contributingGoal = nil }
        }
        .task {
            if viewModel == nil { viewModel = SavingsGoalsViewModel(modelContext: modelContext) }
            viewModel?.load()
        }
    }
}

private struct GoalCard: View {
    let goal: SavingsGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: goal.sfSymbolName)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color(hex: goal.colorHex), in: Circle())
                Text(goal.name).fontWeight(.semibold)
                Spacer()
                if goal.isComplete {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }

            ProgressView(value: goal.progress)
                .tint(Color(hex: goal.colorHex))

            HStack {
                Text("\(CurrencyFormatter.string(from: goal.currentAmount)) of \(CurrencyFormatter.string(from: goal.targetAmount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(goal.progress * 100))%")
                    .font(.caption.bold())
            }

            if let monthly = goal.requiredMonthlyContribution, let targetDate = goal.targetDate {
                Text("Save \(CurrencyFormatter.string(from: monthly))/mo to reach it by \(DateFormatting.medium(targetDate))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { SavingsGoalsView() }
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
