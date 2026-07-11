import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ReportsViewModel {
    struct CategorySpending: Identifiable {
        var id: String { name }
        let name: String
        let colorHex: String
        let amount: Decimal
        /// The category behind this row, so a tapped doughnut slice/legend row can drill into its
        /// transactions for the selected range. Nil for the synthetic "Uncategorized" bucket.
        let category: Category?
    }

    struct MonthlyFlow: Identifiable {
        var id: Date { month }
        let month: Date
        let income: Decimal
        let expense: Decimal
        var net: Decimal { income - expense }
    }

    var range: ReportDateRange = .thisMonth { didSet { load() } }
    var customStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now { didSet { if range == .custom { load() } } }
    var customEnd: Date = .now { didSet { if range == .custom { load() } } }

    private(set) var categorySpending: [CategorySpending] = []
    private(set) var monthlyFlows: [MonthlyFlow] = []
    private(set) var netWorthPoints: [NetWorthCalculator.Point] = []
    private(set) var totalIncome: Decimal = 0
    private(set) var totalExpense: Decimal = 0
    private(set) var hasData = false

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var net: Decimal { totalIncome - totalExpense }

    var topCategory: CategorySpending? { categorySpending.first }

    /// The date range currently in view — used to scope a category drill-down to what the chart shows.
    var currentInterval: DateInterval { range.interval(customStart: customStart, customEnd: customEnd) }

    /// Human label for the current range (e.g. "Last 3 Months"), shown as the drill-down subtitle.
    var rangeLabel: String { range.displayName }

    /// Month-over-month change in spending between the two most recent months in range.
    var monthOverMonthDelta: (previous: Decimal, current: Decimal)? {
        guard monthlyFlows.count >= 2 else { return nil }
        let sorted = monthlyFlows.sorted { $0.month < $1.month }
        return (sorted[sorted.count - 2].expense, sorted[sorted.count - 1].expense)
    }

    func load() {
        let interval = range.interval(customStart: customStart, customEnd: customEnd)

        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)])
        let allTransactions = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter(\.countsTowardTotals)
        let inRange = allTransactions.filter { $0.date >= interval.start && $0.date < interval.end }

        computeCategorySpending(inRange)
        computeMonthlyFlows(inRange, interval: interval)

        totalIncome = inRange.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
        totalExpense = inRange.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + (-$1.amount) }

        let accounts = ((try? modelContext.fetch(FetchDescriptor<Account>())) ?? []).filter { !$0.isArchived }
        netWorthPoints = NetWorthCalculator.monthlySeries(accounts: accounts, transactions: allTransactions, interval: interval)

        hasData = !inRange.isEmpty
    }

    private func computeCategorySpending(_ transactions: [Transaction]) {
        // (category name, colorHex) -> summed expense magnitude, attributing split allocations
        // to their own categories. Alongside the totals, keep the transactions themselves so a
        // category row can expand into its list.
        var totals: [String: (colorHex: String, amount: Decimal, category: Category?)] = [:]

        func add(category: Category?, amount: Decimal) {
            guard amount < 0 else { return }
            let name = category?.name ?? "Uncategorized"
            let colorHex = category?.colorHex ?? "#8E8E93"
            let existing = totals[name] ?? (colorHex, 0, category)
            // Keep the first real category seen for this name so the slice can drill in.
            totals[name] = (existing.colorHex, existing.amount + (-amount), existing.category ?? category)
        }

        for transaction in transactions {
            if transaction.isSplit {
                for split in transaction.splits {
                    add(category: split.category, amount: split.amount)
                }
            } else {
                add(category: transaction.category, amount: transaction.amount)
            }
        }

        categorySpending = totals
            .map { CategorySpending(name: $0.key, colorHex: $0.value.colorHex, amount: $0.value.amount, category: $0.value.category) }
            .sorted { $0.amount > $1.amount }
    }

    private func computeMonthlyFlows(_ transactions: [Transaction], interval: DateInterval) {
        let calendar = Calendar.current
        var buckets: [Date: (income: Decimal, expense: Decimal)] = [:]

        for transaction in transactions {
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.date)) ?? transaction.date
            var bucket = buckets[month] ?? (0, 0)
            if transaction.amount > 0 {
                bucket.income += transaction.amount
            } else {
                bucket.expense += (-transaction.amount)
            }
            buckets[month] = bucket
        }

        monthlyFlows = buckets
            .map { MonthlyFlow(month: $0.key, income: $0.value.income, expense: $0.value.expense) }
            .sorted { $0.month < $1.month }
    }
}
