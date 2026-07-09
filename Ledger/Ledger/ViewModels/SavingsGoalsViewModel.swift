import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SavingsGoalsViewModel {
    private(set) var goals: [SavingsGoal] = []
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load() {
        let descriptor = FetchDescriptor<SavingsGoal>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        goals = (try? modelContext.fetch(descriptor)) ?? []
    }

    func addGoal(name: String, sfSymbolName: String, colorHex: String, targetAmount: Decimal, currentAmount: Decimal, targetDate: Date?) {
        let goal = SavingsGoal(
            name: name,
            sfSymbolName: sfSymbolName,
            colorHex: colorHex,
            targetAmount: targetAmount,
            currentAmount: currentAmount,
            targetDate: targetDate
        )
        modelContext.insert(goal)
        save()
    }

    func updateGoal(_ goal: SavingsGoal, name: String, sfSymbolName: String, colorHex: String, targetAmount: Decimal, currentAmount: Decimal, targetDate: Date?) {
        goal.name = name
        goal.sfSymbolName = sfSymbolName
        goal.colorHex = colorHex
        goal.targetAmount = targetAmount
        goal.currentAmount = currentAmount
        goal.targetDate = targetDate
        save()
    }

    func addContribution(_ amount: Decimal, to goal: SavingsGoal) {
        goal.currentAmount += amount
        save()
    }

    func delete(_ goal: SavingsGoal) {
        modelContext.delete(goal)
        save()
    }

    private func save() {
        try? modelContext.save()
        load()
    }
}
