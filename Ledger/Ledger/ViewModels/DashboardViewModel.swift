import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class DashboardViewModel {
    struct CategorySlice: Identifiable {
        var id: String { name }
        let name: String
        let colorHex: String
        let amount: Decimal
        /// The category behind this slice, so a tapped doughnut slice can drill into its
        /// transactions. Nil for the synthetic "Uncategorized" bucket.
        let category: Category?
    }

    /// One category's budget vs. spending, for the dashboard's clay channel list.
    struct DashBudgetRow: Identifiable {
        let name: String
        let symbol: String
        let spent: Decimal
        let allocated: Decimal
        let category: Category?

        var id: String { name }
        var progress: Double {
            guard allocated > 0 else { return spent > 0 ? 1 : 0 }
            return min((spent as NSDecimalNumber).doubleValue / (allocated as NSDecimalNumber).doubleValue, 1.5)
        }
        var isOver: Bool { spent > allocated && allocated > 0 }
    }

    private(set) var accounts: [Account] = []
    private(set) var recentTransactions: [Transaction] = []
    private(set) var monthSpending: Decimal = 0
    private(set) var monthIncome: Decimal = 0
    private(set) var monthBudgetTotal: Decimal = 0
    private(set) var safeToSpend: Decimal = 0
    /// Upcoming bills + detected recurring charges reserved out of Safe to Spend this month.
    private(set) var reservedForBills: Decimal = 0
    private(set) var topCategories: [CategorySlice] = []
    /// The Financial Wellness score + factors, for the dashboard's Wellness card.
    private(set) var wellness: WellnessResult = .empty
    /// The single most important on-device insight, surfaced as the "Ask Ledger" briefing.
    private(set) var topInsight: Insight?
    /// Per-category budget progress for the dashboard's clay channel list.
    private(set) var budgetRows: [DashBudgetRow] = []
    /// Whole-percent of the month's total budget used, shown inside the balance blob.
    private(set) var budgetUsedPercent: Int = 0
    /// Average spend per elapsed day this month, e.g. "$137/day".
    private(set) var dailyBurnText: String = ""
    /// 0…1 position of the burn-rate marker along the cool→hot meter.
    private(set) var burnPosition: Double = 0.5

    /// Income minus spending for the current month.
    var monthNet: Decimal { monthIncome - monthSpending }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var totalBalance: Decimal {
        accounts.reduce(Decimal(0)) { $0 + $1.currentBalance }
    }

    func load() {
        let accountDescriptor = FetchDescriptor<Account>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        accounts = (try? modelContext.fetch(accountDescriptor)) ?? []

        let calendar = Calendar.current
        let monthStart = Budget.normalize(.now)
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1), to: monthStart) ?? monthStart

        let transactionDescriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let allTransactions = ((try? modelContext.fetch(transactionDescriptor)) ?? [])
            .filter(\.countsTowardTotals)
        recentTransactions = Array(allTransactions.prefix(5))

        let monthTransactions = allTransactions.filter { $0.date >= monthStart && $0.date < monthEnd }
        // Transfers between accounts aren't income or spending, so keep them out of these totals.
        let nonTransfer = monthTransactions.filter { !$0.isTransfer }
        monthSpending = nonTransfer.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + (-$1.amount) }
        monthIncome = nonTransfer.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
        topCategories = computeTopCategories(nonTransfer)

        let budgetDescriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.month == monthStart })
        let budgets = (try? modelContext.fetch(budgetDescriptor)) ?? []
        monthBudgetTotal = budgets.reduce(Decimal(0)) { $0 + $1.allocatedAmount }

        // Per-category budget channels, the balance blob's percent, and the burn-rate meter.
        budgetRows = computeBudgetRows(budgets: budgets, monthTransactions: nonTransfer)
        let budgetDouble = (monthBudgetTotal as NSDecimalNumber).doubleValue
        let spentDouble = (monthSpending as NSDecimalNumber).doubleValue
        budgetUsedPercent = budgetDouble > 0 ? Int((spentDouble / budgetDouble * 100).rounded()) : 0

        let daysInMonth = Double(calendar.range(of: .day, in: .month, for: .now)?.count ?? 30)
        let elapsed = Double(min(max(calendar.component(.day, from: .now), 1), Int(daysInMonth)))
        let perDay = elapsed > 0 ? spentDouble / elapsed : spentDouble
        dailyBurnText = CurrencyFormatter.string(from: Decimal(perDay.rounded())) + "/day"
        burnPosition = budgetDouble > 0 ? min(max((perDay * daysInMonth / budgetDouble) / 1.5, 0.06), 0.96) : 0.5

        // Reserve money that's already spoken for — upcoming bills and detected recurring
        // charges — so Safe to Spend never shows rent money as spendable.
        let bills = (try? modelContext.fetch(FetchDescriptor<BillReminder>())) ?? []
        let recurring = (try? modelContext.fetch(FetchDescriptor<RecurringSeries>())) ?? []
        reservedForBills = SafeToSpendCalculator.upcomingCommitments(bills: bills, recurring: recurring)

        safeToSpend = SafeToSpendCalculator.calculate(
            income: monthIncome,
            budgetAllocations: monthBudgetTotal,
            committedBills: reservedForBills
        )

        // Financial Wellness + the day's "Ask Ledger" briefing, both computed on-device.
        wellness = WellnessScore.evaluate(modelContext: modelContext)
        topInsight = computeTopInsight()
    }

    /// The single highest-priority insight for the Ask Ledger card. Read-only: it generates from
    /// current data and respects dismiss/snooze state, but doesn't re-run recurring detection (that
    /// happens on the Ask Ledger screen), so the dashboard stays cheap to load.
    private func computeTopInsight() -> Insight? {
        let now = Date()
        let transactions = ((try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? [])
            .filter(\.countsTowardTotals)
        let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        let recurring = (try? modelContext.fetch(FetchDescriptor<RecurringSeries>())) ?? []
        let monthStart = Budget.normalize(now)
        let budgets = (try? modelContext.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.month == monthStart }))) ?? []

        let engine = InsightsEngine(
            now: now,
            transactions: transactions,
            categories: categories,
            currentMonthBudgets: budgets,
            recurringSeries: recurring
        )
        let states = (try? modelContext.fetch(FetchDescriptor<InsightState>())) ?? []
        let hidden = Dictionary(states.map { ($0.insightId, $0) }, uniquingKeysWith: { first, _ in first })
        return engine.generate()
            .filter { !(hidden[$0.id]?.isHidden(asOf: now) ?? false) }
            .sorted { $0.severity != $1.severity ? $0.severity > $1.severity : $0.rankValue > $1.rankValue }
            .first
    }

    /// The month's biggest spending categories (split-aware), for the dashboard breakdown chart.
    private func computeTopCategories(_ transactions: [Transaction]) -> [CategorySlice] {
        var totals: [String: (colorHex: String, amount: Decimal, category: Category?)] = [:]

        // Accumulate inline rather than through a nested function: passing the non-Sendable
        // `Category` into a local function that captures `totals` trips Swift 6's region-based
        // data-race check, even though this all runs on the main actor.
        for transaction in transactions {
            let entries: [(category: Category?, amount: Decimal)] = transaction.isSplit
                ? transaction.splits.map { (category: $0.category, amount: $0.amount) }
                : [(category: transaction.category, amount: transaction.amount)]
            for (category, amount) in entries {
                guard amount < 0, category?.isTransfer != true else { continue }
                let name = category?.name ?? "Uncategorized"
                let colorHex = category?.colorHex ?? "#8E8E93"
                let existing = totals[name] ?? (colorHex, 0, category)
                // Keep the first real category seen for this name so the slice can drill in.
                totals[name] = (existing.colorHex, existing.amount + (-amount), existing.category ?? category)
            }
        }

        return totals
            .map { CategorySlice(name: $0.key, colorHex: $0.value.colorHex, amount: $0.value.amount, category: $0.value.category) }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
    }

    /// Per-category budget vs. spending for the month (split-aware), over-budget first then by
    /// allocation, capped at five rows for the dashboard's channel card.
    private func computeBudgetRows(budgets: [Budget], monthTransactions: [Transaction]) -> [DashBudgetRow] {
        var spentByID: [PersistentIdentifier: Decimal] = [:]
        for transaction in monthTransactions {
            if transaction.isSplit {
                for split in transaction.splits {
                    guard let category = split.category, split.amount < 0 else { continue }
                    spentByID[category.persistentModelID, default: 0] += -split.amount
                }
            } else {
                guard let category = transaction.category, transaction.amount < 0 else { continue }
                spentByID[category.persistentModelID, default: 0] += -transaction.amount
            }
        }

        return budgets
            .compactMap { budget -> DashBudgetRow? in
                guard let category = budget.category, budget.allocatedAmount > 0 else { return nil }
                let spent = spentByID[category.persistentModelID] ?? 0
                return DashBudgetRow(
                    name: category.name,
                    symbol: category.sfSymbolName,
                    spent: spent,
                    allocated: budget.allocatedAmount,
                    category: category
                )
            }
            .sorted { lhs, rhs in
                lhs.isOver != rhs.isOver ? lhs.isOver : lhs.allocated > rhs.allocated
            }
            .prefix(5)
            .map { $0 }
    }
}
