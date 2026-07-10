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
            // A $0 budget with spending is over budget: show a full bar, not an empty one.
            guard allocatedIncludingRollover > 0 else { return spent > 0 ? 1 : 0 }
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

    /// Builds budgets for the selected month from the average monthly spend of each expense category
    /// over the preceding `months` calendar months. Categories with no spend in the window are left
    /// alone; existing budgets for the month are updated in place. Returns how many were set.
    @discardableResult
    func generateFromRecentHistory(months: Int = 3) -> Int {
        let calendar = Calendar.current
        let month = selectedMonth
        guard let windowStart = calendar.date(byAdding: .month, value: -months, to: month) else { return 0 }

        let allTransactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        let inWindow = allTransactions.filter { $0.date >= windowStart && $0.date < month && $0.amount < 0 }

        var totals: [PersistentIdentifier: Decimal] = [:]
        for transaction in inWindow {
            guard let category = transaction.category, !category.isIncome else { continue }
            totals[category.persistentModelID, default: 0] += -transaction.amount
        }
        guard !totals.isEmpty else { return 0 }

        let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        let categoriesById = Dictionary(categories.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })

        let existing = (try? modelContext.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.month == month }))) ?? []
        var existingByCategory: [PersistentIdentifier: Budget] = [:]
        for budget in existing where budget.category != nil {
            existingByCategory[budget.category!.persistentModelID] = budget
        }

        var count = 0
        for (categoryId, total) in totals {
            guard let category = categoriesById[categoryId] else { continue }
            let average = Self.roundedToDollar(total / Decimal(months))
            guard average > 0 else { continue }
            if let budget = existingByCategory[categoryId] {
                budget.allocatedAmount = average
            } else {
                modelContext.insert(Budget(month: month, category: category, allocatedAmount: average))
            }
            count += 1
        }

        try? modelContext.save()
        load()
        return count
    }

    private static func roundedToDollar(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }
}
