import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class BudgetsViewModel {
    struct BudgetRow: Identifiable {
        var id: PersistentIdentifier { budget.persistentModelID }
        let budget: Budget
        let spent: Decimal
        let rolloverFromPreviousMonth: Decimal

        var allocatedIncludingRollover: Decimal { budget.allocatedAmount + rolloverFromPreviousMonth }
        var remaining: Decimal { allocatedIncludingRollover - spent }
        var isOverBudget: Bool { spent > allocatedIncludingRollover }

        var progress: Double {
            guard allocatedIncludingRollover > 0 else { return 0 }
            let value = (spent as NSDecimalNumber).doubleValue / (allocatedIncludingRollover as NSDecimalNumber).doubleValue
            return min(max(value, 0), 1.5)
        }
    }

    private(set) var rows: [BudgetRow] = []
    var selectedMonth: Date = Budget.normalize(.now) {
        didSet { load() }
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load() {
        let month = selectedMonth
        let budgetDescriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.month == month })
        let budgets = (try? modelContext.fetch(budgetDescriptor)) ?? []

        let allTransactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []

        let calendar = Calendar.current
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1), to: month) ?? month
        let previousMonth = calendar.date(byAdding: DateComponents(month: -1), to: month) ?? month

        rows = budgets.map { budget in
            let categoryId = budget.category?.persistentModelID
            let spent = allTransactions
                .filter { $0.date >= month && $0.date < monthEnd && $0.amount < 0 && $0.category?.persistentModelID == categoryId }
                .reduce(Decimal(0)) { $0 + (-$1.amount) }

            var rollover: Decimal = 0
            if budget.rolloverEnabled {
                let previousDescriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.month == previousMonth })
                let previousBudget = (try? modelContext.fetch(previousDescriptor))?
                    .first { $0.category?.persistentModelID == categoryId }
                if let previousBudget {
                    let previousSpent = allTransactions
                        .filter { $0.date >= previousMonth && $0.date < month && $0.amount < 0 && $0.category?.persistentModelID == categoryId }
                        .reduce(Decimal(0)) { $0 + (-$1.amount) }
                    rollover = max(previousBudget.allocatedAmount - previousSpent, 0)
                }
            }

            return BudgetRow(budget: budget, spent: spent, rolloverFromPreviousMonth: rollover)
        }
        .sorted { ($0.budget.category?.name ?? "") < ($1.budget.category?.name ?? "") }
    }

    func addOrUpdateBudget(category: Category, allocatedAmount: Decimal, rolloverEnabled: Bool) {
        let month = selectedMonth
        let categoryId = category.persistentModelID
        let descriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.month == month })
        let existing = (try? modelContext.fetch(descriptor))?.first { $0.category?.persistentModelID == categoryId }

        if let existing {
            existing.allocatedAmount = allocatedAmount
            existing.rolloverEnabled = rolloverEnabled
        } else {
            let budget = Budget(month: month, category: category, allocatedAmount: allocatedAmount, rolloverEnabled: rolloverEnabled)
            modelContext.insert(budget)
        }
        try? modelContext.save()
        load()
    }

    func delete(_ row: BudgetRow) {
        modelContext.delete(row.budget)
        try? modelContext.save()
        load()
    }
}
