import Foundation
import SwiftData

/// A snapshot of the user's finances that Ask Ledger reasons over. Built once per session from the
/// model layer so the engine stays pure and everything is answered from the user's real, on-device
/// data — never a generic model with no context.
@MainActor
struct AskLedgerContext {
    struct CategorySpend { let name: String; let amount: Decimal }
    struct BudgetLine { let name: String; let spent: Decimal; let allocated: Decimal }
    struct Subscription { let name: String; let monthly: Decimal; let cadence: String; let annual: Double }
    struct DebtItem { let name: String; let balance: Decimal; let apr: Double; let minPayment: Decimal }
    struct GoalItem {
        let name: String; let saved: Decimal; let target: Decimal; let progress: Double
        let requiredMonthly: Decimal?; let targetDate: Date?
    }

    var monthName = ""
    var totalBalance: Decimal = 0
    var accountCount = 0
    var monthIncome: Decimal = 0
    var monthSpending: Decimal = 0
    var safeToSpend: Decimal = 0
    var reservedForBills: Decimal = 0
    var budgetTotal: Decimal = 0
    var budgetUsedPercent = 0
    var savingsRate: Double = 0
    var emergencyMonths: Double = 0
    var projectedSpending: Decimal = 0
    var daysLeftInMonth = 0

    var categoriesThisMonth: [CategorySpend] = []
    var categoriesLastMonth: [String: Decimal] = [:]
    var budgetLines: [BudgetLine] = []
    var subscriptions: [Subscription] = []
    var subscriptionMonthly: Decimal = 0
    var debts: [DebtItem] = []
    var goals: [GoalItem] = []
    var wellness: WellnessResult = .empty

    var monthNet: Decimal { monthIncome - monthSpending }
    var hasData: Bool { accountCount > 0 || !categoriesThisMonth.isEmpty }

    static func build(modelContext: ModelContext, now: Date = .now, calendar: Calendar = .current) -> AskLedgerContext {
        var ctx = AskLedgerContext()
        ctx.monthName = DateFormatting.monthYear(now)

        let accounts = ((try? modelContext.fetch(FetchDescriptor<Account>(predicate: #Predicate { !$0.isArchived }))) ?? [])
        ctx.accountCount = accounts.count
        ctx.totalBalance = accounts.reduce(Decimal(0)) { $0 + $1.currentBalance }

        let allTx = ((try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? [])
            .filter { $0.countsTowardTotals && !$0.isTransfer }

        let monthStart = Budget.normalize(now)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart

        let thisMonth = allTx.filter { $0.date >= monthStart && $0.date < monthEnd }
        let lastMonth = allTx.filter { $0.date >= lastMonthStart && $0.date < monthStart }

        ctx.monthSpending = thisMonth.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + (-$1.amount) }
        ctx.monthIncome = thisMonth.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
        ctx.savingsRate = ctx.monthIncome > 0 ? dv(ctx.monthNet) / dv(ctx.monthIncome) : 0

        let thisByCat = expenseByCategory(thisMonth)
        ctx.categoriesThisMonth = thisByCat
            .map { CategorySpend(name: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
        ctx.categoriesLastMonth = expenseByCategory(lastMonth)

        let budgets = ((try? modelContext.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.month == monthStart }))) ?? [])
        ctx.budgetTotal = budgets.reduce(Decimal(0)) { $0 + $1.allocatedAmount }
        ctx.budgetLines = budgets.compactMap { budget in
            guard let category = budget.category, budget.allocatedAmount > 0 else { return nil }
            let spent = thisByCat[category.name] ?? 0
            return BudgetLine(name: category.name, spent: spent, allocated: budget.allocatedAmount)
        }
        .sorted { dv($0.spent) / max(dv($0.allocated), 1) > dv($1.spent) / max(dv($1.allocated), 1) }
        ctx.budgetUsedPercent = ctx.budgetTotal > 0 ? Int((dv(ctx.monthSpending) / dv(ctx.budgetTotal) * 100).rounded()) : 0

        let bills = (try? modelContext.fetch(FetchDescriptor<BillReminder>())) ?? []
        let recurring = (try? modelContext.fetch(FetchDescriptor<RecurringSeries>())) ?? []
        ctx.reservedForBills = SafeToSpendCalculator.upcomingCommitments(bills: bills, recurring: recurring, now: now, calendar: calendar)
        ctx.safeToSpend = SafeToSpendCalculator.calculate(income: ctx.monthIncome, budgetAllocations: ctx.budgetTotal, committedBills: ctx.reservedForBills)

        let subs = recurring.filter { $0.isActive && !$0.isIncome }
        ctx.subscriptions = subs.map { series in
            let annual = abs(dv(series.averageAmount)) * 365.0 / Double(max(series.cadence.approximateDays, 1))
            return Subscription(name: series.displayName, monthly: Decimal(annual / 12), cadence: series.cadence.displayName, annual: annual)
        }
        .sorted { $0.annual > $1.annual }
        ctx.subscriptionMonthly = ctx.subscriptions.reduce(Decimal(0)) { $0 + $1.monthly }

        ctx.debts = ((try? modelContext.fetch(FetchDescriptor<Debt>(predicate: #Predicate { !$0.isArchived }))) ?? [])
            .map { DebtItem(name: $0.name, balance: $0.currentBalance, apr: $0.annualInterestRate, minPayment: $0.minimumPayment) }
            .sorted { $0.apr > $1.apr }

        ctx.goals = ((try? modelContext.fetch(FetchDescriptor<SavingsGoal>(predicate: #Predicate { !$0.isArchived }))) ?? [])
            .map { GoalItem(name: $0.name, saved: $0.savedAmount, target: $0.targetAmount, progress: $0.progress, requiredMonthly: $0.requiredMonthlyContribution, targetDate: $0.targetDate) }

        // Emergency-fund coverage in months of expenses.
        let priorStart = calendar.date(byAdding: .month, value: -3, to: monthStart) ?? monthStart
        let priorSpend = allTx.filter { $0.date >= priorStart && $0.date < monthStart && $0.amount < 0 }
            .reduce(Decimal(0)) { $0 + (-$1.amount) }
        let avgMonthlyExpenses = priorSpend > 0 ? dv(priorSpend) / 3 : dv(ctx.monthSpending)
        let liquidSavings = dv(accounts.filter { $0.type == .savings }.reduce(Decimal(0)) { $0 + max($1.currentBalance, 0) })
        ctx.emergencyMonths = avgMonthlyExpenses > 0 ? liquidSavings / avgMonthlyExpenses : (liquidSavings > 0 ? 6 : 0)

        let daysInMonth = Double(calendar.range(of: .day, in: .month, for: now)?.count ?? 30)
        let elapsed = Double(min(max(calendar.component(.day, from: now), 1), Int(daysInMonth)))
        ctx.projectedSpending = Decimal(dv(ctx.monthSpending) * daysInMonth / max(elapsed, 1))
        ctx.daysLeftInMonth = max(Int(daysInMonth - elapsed), 0)

        ctx.wellness = WellnessScore.evaluate(modelContext: modelContext, now: now, calendar: calendar)
        return ctx
    }

    // MARK: - Helpers

    /// Split-aware expense magnitude per category name over a set of transactions.
    private static func expenseByCategory(_ transactions: [Transaction]) -> [String: Decimal] {
        var totals: [String: Decimal] = [:]
        for transaction in transactions {
            if transaction.isSplit {
                for split in transaction.splits where split.amount < 0 && split.category?.isTransfer != true {
                    totals[split.category?.name ?? "Uncategorized", default: 0] += -split.amount
                }
            } else if transaction.amount < 0, transaction.category?.isTransfer != true {
                totals[transaction.category?.name ?? "Uncategorized", default: 0] += -transaction.amount
            }
        }
        return totals
    }

    private static func dv(_ value: Decimal) -> Double { (value as NSDecimalNumber).doubleValue }
}
