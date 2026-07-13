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
        repairDanglingAccountLinks()
        let descriptor = FetchDescriptor<SavingsGoal>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        goals = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Heals goals left pointing at a deleted account by earlier versions (before account deletion
    /// unlinked them). Reading such a goal's `account.currentBalance` crashes, so this must run
    /// before the cards render. Only the relationship's identifier is read here — never the
    /// account's data properties — so it's safe even when the target row is gone: a goal whose
    /// account id is no longer in the store is dropped back to a manual/unlinked goal.
    private func repairDanglingAccountLinks() {
        let allGoals = (try? modelContext.fetch(FetchDescriptor<SavingsGoal>())) ?? []
        let validAccountIDs = Set(((try? modelContext.fetch(FetchDescriptor<Account>())) ?? []).map(\.persistentModelID))
        var didRepair = false
        for goal in allGoals {
            guard let accountID = goal.account?.persistentModelID else { continue }
            if !validAccountIDs.contains(accountID) {
                goal.account = nil
                didRepair = true
            }
        }
        if didRepair { try? modelContext.save() }
    }

    func addGoal(name: String, sfSymbolName: String, colorHex: String, targetAmount: Decimal, currentAmount: Decimal, targetDate: Date?, account: Account?) {
        let goal = SavingsGoal(
            name: name,
            sfSymbolName: sfSymbolName,
            colorHex: colorHex,
            targetAmount: targetAmount,
            currentAmount: currentAmount,
            targetDate: targetDate,
            account: account
        )
        modelContext.insert(goal)
        save()
    }

    func updateGoal(_ goal: SavingsGoal, name: String, sfSymbolName: String, colorHex: String, targetAmount: Decimal, currentAmount: Decimal, targetDate: Date?, account: Account?) {
        goal.name = name
        goal.sfSymbolName = sfSymbolName
        goal.colorHex = colorHex
        goal.targetAmount = targetAmount
        goal.currentAmount = currentAmount
        goal.targetDate = targetDate
        goal.account = account
        save()
    }

    /// Manual goals only — an account-tracked goal moves when money lands in the account.
    func addContribution(_ amount: Decimal, to goal: SavingsGoal) {
        guard !goal.isAccountTracked else { return }
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
