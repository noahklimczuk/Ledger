import SwiftUI
import SwiftData

struct SavingsGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SavingsGoalsViewModel?
    @State private var isPresentingNew = false
    @State private var editingGoal: SavingsGoal?
    @State private var contributingGoal: SavingsGoal?

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
                            GoalCard(goal: goal) {
                                contributingGoal = goal
                            }
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
                            // Long-press menu, so every action stays reachable where the paged
                            // tab swipe competes with row swipes.
                            .contextMenu {
                                Button {
                                    contributingGoal = goal
                                } label: {
                                    Label("Add Money", systemImage: "plus.circle.fill")
                                }
                                Button {
                                    editingGoal = goal
                                } label: {
                                    Label("Edit Goal", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    viewModel.delete(goal)
                                } label: {
                                    Label("Delete Goal", systemImage: "trash")
                                }
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
        .sheet(item: $contributingGoal, onDismiss: { viewModel?.load() }) { goal in
            GoalContributionView(goal: goal)
        }
        .task {
            if viewModel == nil { viewModel = SavingsGoalsViewModel(modelContext: modelContext) }
            viewModel?.load()
        }
    }
}

private struct GoalCard: View {
    let goal: SavingsGoal
    let onAddMoney: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: goal.sfSymbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color(hex: goal.colorHex), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(goal.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(goal.isComplete
                         ? "Goal reached 🎉"
                         : "\(CurrencyFormatter.string(from: goal.remaining)) to go")
                        .font(.caption)
                        .foregroundStyle(goal.isComplete ? Color.green : Color.secondary)
                }
                Spacer()
                Text("\(Int(goal.progress * 100))%")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(goal.isComplete ? Color.green : Color(hex: goal.colorHex))
            }

            ProgressView(value: goal.progress)
                .tint(Color(hex: goal.colorHex))

            HStack {
                Text("\(CurrencyFormatter.string(from: goal.currentAmount)) of \(CurrencyFormatter.string(from: goal.targetAmount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let monthly = goal.requiredMonthlyContribution, let targetDate = goal.targetDate {
                    Text("\(CurrencyFormatter.string(from: monthly))/mo by \(DateFormatting.medium(targetDate))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !goal.isComplete {
                Button(action: onAddMoney) {
                    Label("Add Money", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color(hex: goal.colorHex))
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack { SavingsGoalsView() }
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
