import Foundation
import Observation
import SwiftData

/// Drives the zero-based Budgets tab: every dollar of the month's income gets assigned to a
/// category until "left to assign" reaches zero. Beyond the per-category rows this computes the
/// month-level plan (income vs. assigned vs. spent), surfaces spending that happened *outside*
/// the plan (unbudgeted categories, uncategorized transactions), and tracks pace through the
/// month so overspending shows up before the month ends.
@MainActor
@Observable
final class BudgetsViewModel {
    struct BudgetRow: Identifiable {
        var id: PersistentIdentifier { budget.persistentModelID }
        let budget: Budget
        /// Net outflow for the category this month (refunds credited back), including any
        /// subcategories that don't carry their own budget.
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

        /// Whole-percent share of the budget used, uncapped so an overrun reads "132%". Nil when
        /// there's nothing allocated to measure against.
        var percentUsed: Int? {
            guard allocatedIncludingRollover > 0 else { return nil }
            let value = (spent as NSDecimalNumber).doubleValue / (allocatedIncludingRollover as NSDecimalNumber).doubleValue
            return max(Int((value * 100).rounded()), 0)
        }
    }

    /// Spending the plan doesn't cover: an expense category with no budget this month, or
    /// (with `category == nil`) transactions that haven't been categorized at all.
    struct UnbudgetedRow: Identifiable {
        let category: Category?
        let spent: Decimal

        var id: PersistentIdentifier? { category?.persistentModelID }
    }

    private(set) var rows: [BudgetRow] = []
    private(set) var unbudgeted: [UnbudgetedRow] = []

    /// Income actually received this month (positive transactions in income categories, plus
    /// uncategorized inflows). Refunds land in their expense category and net against spending
    /// there instead of inflating income.
    private(set) var actualIncome: Decimal = 0
    /// User-set planning amount for the month, when they've chosen not to plan off actual income.
    private(set) var incomeOverride: Decimal?
    /// How far through the month we are, 0…1 (0 for future months, 1 for past ones).
    private(set) var monthProgress: Double = 0
    /// Days left including today — only meaningful when viewing the current month, else nil.
    private(set) var daysRemaining: Int?

    var selectedMonth: Date = Budget.normalize(.now) {
        didSet { load() }
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Zero-based plan aggregates

    /// The pot of money the plan assigns from.
    var incomeToAssign: Decimal { incomeOverride ?? actualIncome }

    /// Sum of this month's assignments. Rollover is deliberately excluded — it's last month's
    /// money arriving on top of the plan, not part of this month's income to assign.
    var totalAllocated: Decimal {
        rows.reduce(Decimal(0)) { $0 + $1.budget.allocatedAmount }
    }

    var totalRollover: Decimal {
        rows.reduce(Decimal(0)) { $0 + $1.rolloverFromPreviousMonth }
    }

    /// Net spending inside budgeted categories.
    var totalSpent: Decimal {
        rows.reduce(Decimal(0)) { $0 + $1.spent }
    }

    /// Net spending outside the plan (unbudgeted categories + uncategorized).
    var totalUnbudgetedSpent: Decimal {
        unbudgeted.reduce(Decimal(0)) { $0 + $1.spent }
    }

    /// The zero-based headline: income minus assignments. Zero means every dollar has a job.
    var leftToAssign: Decimal { incomeToAssign - totalAllocated }

    var totalAvailable: Decimal { totalAllocated + totalRollover }

    var totalRemaining: Decimal { totalAvailable - totalSpent }

    var overBudgetCount: Int { rows.filter(\.isOverBudget).count }

    var overallProgress: Double {
        guard totalAvailable > 0 else { return totalSpent > 0 ? 1 : 0 }
        let value = (totalSpent as NSDecimalNumber).doubleValue / (totalAvailable as NSDecimalNumber).doubleValue
        return min(max(value, 0), 1.5)
    }

    var isOverallOverBudget: Bool { totalSpent > totalAvailable && totalAvailable >= 0 && totalSpent > 0 }

    // MARK: - Loading

    /// How many months back a rollover chain is followed. Bounds the per-load work; a year of
    /// history is plenty for a monthly budgeting habit.
    private static let rolloverLookbackMonths = 12

    func load() {
        let calendar = Calendar.current
        let month = selectedMonth
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1), to: month) ?? month

        let budgets = (try? modelContext.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.month == month }))) ?? []
        let allTransactions = ((try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? [])
            .filter(\.countsTowardTotals)

        // Budgets over the rollover lookback window, bucketed by month, so a chain of
        // rollover-enabled months can be followed backwards from the selected month.
        let chainStart = calendar.date(byAdding: .month, value: -Self.rolloverLookbackMonths, to: month) ?? month
        let chainBudgets = (try? modelContext.fetch(FetchDescriptor<Budget>(
            predicate: #Predicate { $0.month >= chainStart && $0.month < month }
        ))) ?? []
        var budgetsByMonth: [Date: [Budget]] = [:]
        for budget in chainBudgets { budgetsByMonth[budget.month, default: []].append(budget) }

        let budgetedIds = Set(budgets.compactMap { $0.category?.persistentModelID })

        // Net outflow per category over a window: outflows minus refunds, so a return credited
        // back to a category frees its budget up again.
        func netOutflow(coveredIds: Set<PersistentIdentifier>, from start: Date, to end: Date) -> Decimal {
            allTransactions
                .filter { transaction in
                    guard !transaction.isTransfer else { return false }
                    guard transaction.date >= start && transaction.date < end else { return false }
                    guard let id = transaction.category?.persistentModelID else { return false }
                    return coveredIds.contains(id)
                }
                .reduce(Decimal(0)) { $0 + (-$1.amount) }
        }

        // A budget on a parent category also covers subcategories that have no budget of their
        // own this month, so subcategory spending never silently escapes the plan.
        func coverage(of category: Category, budgeted: Set<PersistentIdentifier>) -> Set<PersistentIdentifier> {
            var ids: Set<PersistentIdentifier> = [category.persistentModelID]
            for sub in category.subcategories where !budgeted.contains(sub.persistentModelID) {
                ids.insert(sub.persistentModelID)
            }
            return ids
        }

        // Leftover budget carried into the selected month, compounding across every consecutive
        // rollover-enabled month before it: each month's carry is
        // max(allocated + carry-in − spent, 0), so unused money keeps accumulating and an
        // overspent month eats into (but never inverts) what was saved up. The chain breaks at
        // the first month without a rollover-enabled budget for the category.
        func rolloverIntoSelectedMonth(for category: Category) -> Decimal {
            let categoryId = category.persistentModelID
            var carry: Decimal = 0
            var cursor = chainStart
            while cursor < month {
                let cursorEnd = calendar.date(byAdding: .month, value: 1, to: cursor) ?? month
                let monthBudgets = budgetsByMonth[cursor] ?? []
                if let budget = monthBudgets.first(where: { $0.category?.persistentModelID == categoryId }),
                   budget.rolloverEnabled {
                    let monthBudgetedIds = Set(monthBudgets.compactMap { $0.category?.persistentModelID })
                    let covered = coverage(of: category, budgeted: monthBudgetedIds)
                    let spent = netOutflow(coveredIds: covered, from: cursor, to: cursorEnd)
                    carry = max(budget.allocatedAmount + carry - spent, 0)
                } else {
                    carry = 0
                }
                cursor = cursorEnd
            }
            return carry
        }

        var coveredIds = Set<PersistentIdentifier>()

        rows = budgets.map { budget in
            guard let category = budget.category else {
                return BudgetRow(budget: budget, spent: 0, rolloverFromPreviousMonth: 0)
            }
            let covered = coverage(of: category, budgeted: budgetedIds)
            coveredIds.formUnion(covered)
            let spent = netOutflow(coveredIds: covered, from: month, to: monthEnd)

            let rollover = budget.rolloverEnabled ? rolloverIntoSelectedMonth(for: category) : 0

            return BudgetRow(budget: budget, spent: spent, rolloverFromPreviousMonth: rollover)
        }
        .sorted { lhs, rhs in
            // Overruns float to the top where they need attention; the rest stay alphabetical.
            if lhs.isOverBudget != rhs.isOverBudget { return lhs.isOverBudget }
            return (lhs.budget.category?.name ?? "") < (rhs.budget.category?.name ?? "")
        }

        loadUnbudgeted(allTransactions: allTransactions, coveredIds: coveredIds, from: month, to: monthEnd)
        loadIncome(allTransactions: allTransactions, from: month, to: monthEnd)
        loadPace(month: month, monthEnd: monthEnd, calendar: calendar)
    }

    private func loadUnbudgeted(allTransactions: [Transaction], coveredIds: Set<PersistentIdentifier>, from start: Date, to end: Date) {
        var byCategory: [PersistentIdentifier: (category: Category, spent: Decimal)] = [:]
        var uncategorized: Decimal = 0

        for transaction in allTransactions where transaction.date >= start && transaction.date < end {
            guard let category = transaction.category else {
                if transaction.amount < 0 { uncategorized += -transaction.amount }
                continue
            }
            let id = category.persistentModelID
            if category.isIncome || category.isTransfer || coveredIds.contains(id) { continue }
            byCategory[id, default: (category, 0)].spent += -transaction.amount
        }

        var result = byCategory.values
            .filter { $0.spent > 0 }
            .map { UnbudgetedRow(category: $0.category, spent: $0.spent) }
            .sorted { $0.spent > $1.spent }
        if uncategorized > 0 {
            result.append(UnbudgetedRow(category: nil, spent: uncategorized))
        }
        unbudgeted = result
    }

    private func loadIncome(allTransactions: [Transaction], from start: Date, to end: Date) {
        actualIncome = allTransactions
            .filter { transaction in
                transaction.date >= start && transaction.date < end && transaction.amount > 0
                    && (transaction.category == nil || transaction.category?.isIncome == true)
            }
            .reduce(Decimal(0)) { $0 + $1.amount }

        let month = selectedMonth
        let period = (try? modelContext.fetch(FetchDescriptor<BudgetPeriod>(predicate: #Predicate { $0.month == month })))?.first
        incomeOverride = period?.expectedIncome
    }

    private func loadPace(month: Date, monthEnd: Date, calendar: Calendar) {
        let now = Date()
        if now >= monthEnd {
            monthProgress = 1
            daysRemaining = nil
        } else if now < month {
            monthProgress = 0
            daysRemaining = nil
        } else {
            let total = monthEnd.timeIntervalSince(month)
            monthProgress = total > 0 ? now.timeIntervalSince(month) / total : 0
            let today = calendar.startOfDay(for: now)
            daysRemaining = max(calendar.dateComponents([.day], from: today, to: monthEnd).day ?? 0, 0)
        }
    }

    // MARK: - Mutations

    /// Sets (or with nil, clears) the month's planned income override.
    func setIncomeOverride(_ amount: Decimal?) {
        let month = selectedMonth
        let existing = (try? modelContext.fetch(FetchDescriptor<BudgetPeriod>(predicate: #Predicate { $0.month == month })))?.first

        if let amount {
            if let existing {
                existing.expectedIncome = amount
            } else {
                modelContext.insert(BudgetPeriod(month: month, expectedIncome: amount))
            }
        } else if let existing {
            modelContext.delete(existing)
        }
        try? modelContext.save()
        load()
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

        let allTransactions = ((try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? [])
            .filter(\.countsTowardTotals)
        let inWindow = allTransactions.filter { $0.date >= windowStart && $0.date < month && $0.amount < 0 }

        var totals: [PersistentIdentifier: Decimal] = [:]
        for transaction in inWindow {
            guard let category = transaction.category, !category.isIncome, !category.isTransfer else { continue }
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
