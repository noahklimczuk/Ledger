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
                            .contentShape(Rectangle())
                            .onTapGesture { editingGoal = goal }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                    viewModel.delete(goal)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingGoal = goal
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Palette.peri)
                            }
                            // Long-press menu, so every action stays reachable where the paged
                            // tab swipe competes with row swipes.
                            .contextMenu {
                                if !goal.isAccountTracked {
                                    Button {
                                        contributingGoal = goal
                                    } label: {
                                        Label("Add Money", systemImage: "plus.circle.fill")
                                    }
                                }
                                Button {
                                    editingGoal = goal
                                } label: {
                                    Label("Edit Goal", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                    viewModel.delete(goal)
                                } label: {
                                    Label("Delete Goal", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Savings Goals")
        .accentWash(.goals)
        .accent(.goals)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Goal")
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

/// A growing plant in a "pot" ring — Bloom's goal metaphor. The ring fills with progress and the
/// plant grows through stages (seed → sprout → tree) as the goal fills.
private struct PlantPot: View {
    let progress: Double
    let emoji: String
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Accent.goals.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(emoji).font(.system(size: size * 0.42))
        }
        .frame(width: size, height: size)
        .animation(Motion.smooth, value: progress)
        .accessibilityHidden(true)
    }
}

private struct GoalCard: View {
    let goal: SavingsGoal
    let onAddMoney: () -> Void

    /// Growth stage from progress: seed → sprout → tree.
    private var plant: String {
        if goal.isComplete { return "🌳" }
        switch goal.progress {
        case ..<0.34: return "🌱"
        case ..<0.67: return "🌿"
        default: return "🌳"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                PlantPot(progress: goal.progress, emoji: plant)
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.name)
                        .font(.appBodyMedium.weight(.bold))
                        .lineLimit(1)
                    Text("\(CurrencyFormatter.string(from: goal.savedAmount)) of \(CurrencyFormatter.string(from: goal.targetAmount)) · \(Int(goal.progress * 100))%")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if goal.isComplete {
                        Text("Fully grown 🎉").font(.appCaption2).foregroundStyle(Palette.income)
                    } else if let monthly = goal.requiredMonthlyContribution, let targetDate = goal.targetDate {
                        Text("\(CurrencyFormatter.string(from: monthly))/mo · by \(DateFormatting.medium(targetDate))")
                            .font(.appCaption2).foregroundStyle(.secondary)
                    } else {
                        Text("\(CurrencyFormatter.string(from: goal.remaining)) to grow")
                            .font(.appCaption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if goal.isAccountTracked {
                    Image(systemName: "link")
                        .font(.appSubheadline.weight(.bold))
                        .foregroundStyle(Accent.goals.base)
                        .accessibilityLabel("Tracks an account automatically")
                } else if !goal.isComplete {
                    Button(action: onAddMoney) {
                        Image(systemName: "plus")
                            .font(.appHeadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Accent.goals.gradient, in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Add money to \(goal.name)")
                }
            }

            if let account = goal.account {
                Label("Tracks \(account.name) automatically", systemImage: "link")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

#Preview {
    NavigationStack { SavingsGoalsView() }
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
