import Foundation
import SwiftData

/// On-device statistical aggregation behind the AI budget proposal. Everything here runs locally:
/// it reduces the last few months of categorized spending to per-category monthly totals,
/// averages, and a simple trend, and derives a baseline suggested budget (including a savings
/// set-aside) from those numbers. The Gemini call (`GeminiService`) sees this summary — the
/// aggregated totals plus recent transaction lines (date, amount, category, merchant) — but never
/// account names, balances, notes, or receipts.
@MainActor
struct BudgetSuggestionService {
    /// Aggregated history for one expense category over the analysis window.
    struct CategoryStat {
        let category: Category
        /// Net outflow per calendar month, oldest first, one entry per month in the window.
        let monthlyTotals: [Decimal]
        let average: Decimal
        /// Average over the most recent half of the window — the trend signal.
        let recentAverage: Decimal
        /// The on-device baseline suggestion (used as-is when the AI path is unavailable).
        let baselineSuggestion: Decimal

        var isTrendingUp: Bool { recentAverage > average * Decimal(1.15) }
        var isTrendingDown: Bool { recentAverage < average * Decimal(0.85) }
    }

    struct Summary {
        let months: Int
        let stats: [CategoryStat]
        let averageMonthlyIncome: Decimal
        /// Monthly-equivalent total of detected recurring charges (subscriptions/bills).
        let monthlyRecurringCommitments: Decimal
        /// On-device baseline for the monthly savings set-aside: the surplus between average
        /// income and the baseline category budgets, so it scales with the income-vs-spending gap.
        let suggestedSavings: Decimal
        /// Recent transactions in the window as compact prompt lines
        /// ("date | amount | category | merchant"), most recent first.
        let recentTransactions: [String]
    }

    /// How many transaction lines are sent to the AI per request; keeps prompts bounded on
    /// heavily imported ledgers.
    static let promptTransactionLimit = 250

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Aggregates the `months` full calendar months preceding `month` (the month being budgeted).
    /// Returns nil when there's no categorized spending to build from.
    func summarize(before month: Date, months: Int = 6) -> Summary? {
        let calendar = Calendar.current
        let monthStart = Budget.normalize(month)
        guard let windowStart = calendar.date(byAdding: .month, value: -months, to: monthStart) else { return nil }

        let transactions = ((try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? [])
            .filter(\.countsTowardTotals)
            .filter { $0.date >= windowStart && $0.date < monthStart }
        guard !transactions.isEmpty else { return nil }

        // Month boundaries, oldest first.
        var boundaries: [Date] = []
        var cursor = windowStart
        while cursor < monthStart {
            boundaries.append(cursor)
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? monthStart
        }
        func monthIndex(of date: Date) -> Int? {
            boundaries.lastIndex { date >= $0 }
        }

        // Net outflow per category per month (refunds credited back), split-aware.
        var totals: [PersistentIdentifier: [Decimal]] = [:]
        var categoriesById: [PersistentIdentifier: Category] = [:]
        var incomeByMonth = [Decimal](repeating: 0, count: boundaries.count)

        // Accumulate inline rather than through a nested function: passing the non-Sendable
        // `Category` into a local function that captures `totals`/`categoriesById` trips Swift 6's
        // region-based data-race check, even though this all runs on the main actor.
        for transaction in transactions {
            guard let idx = monthIndex(of: transaction.date) else { continue }
            let entries: [(category: Category?, amount: Decimal)] = transaction.isSplit
                ? transaction.splits.map { (category: $0.category, amount: $0.amount) }
                : [(category: transaction.category, amount: transaction.amount)]
            for (category, amount) in entries {
                // Transfers between accounts are neither spending nor income — skip them entirely.
                if category?.isTransfer == true { continue }
                if let category, !category.isIncome {
                    categoriesById[category.persistentModelID] = category
                    var series = totals[category.persistentModelID] ?? [Decimal](repeating: 0, count: boundaries.count)
                    series[idx] += -amount
                    totals[category.persistentModelID] = series
                } else if amount > 0, category == nil || category?.isIncome == true {
                    incomeByMonth[idx] += amount
                }
            }
        }

        let stats = totals.compactMap { id, series -> CategoryStat? in
            guard let category = categoriesById[id] else { return nil }
            // Months where refunds exceeded spending count as zero, not negative.
            let clamped = series.map { max($0, 0) }
            let total = clamped.reduce(Decimal(0), +)
            guard total > 0 else { return nil }
            let average = total / Decimal(clamped.count)
            let recentHalf = Array(clamped.suffix(max(clamped.count / 2, 1)))
            let recentAverage = recentHalf.reduce(Decimal(0), +) / Decimal(recentHalf.count)
            return CategoryStat(
                category: category,
                monthlyTotals: clamped,
                average: Self.roundedToDollar(average),
                recentAverage: Self.roundedToDollar(recentAverage),
                baselineSuggestion: Self.baseline(average: average, recentAverage: recentAverage)
            )
        }
        .sorted { $0.average > $1.average }
        guard !stats.isEmpty else { return nil }

        let income = incomeByMonth.reduce(Decimal(0), +) / Decimal(max(incomeByMonth.count, 1))

        let recurring = ((try? modelContext.fetch(FetchDescriptor<RecurringSeries>())) ?? [])
            .filter { !$0.isIgnored && !$0.isIncome }
            .reduce(Decimal(0)) { total, series in
                // Monthly equivalent: a weekly charge counts ~4.3x, a yearly one ~1/12.
                total + (-series.averageAmount) * Decimal(30.44) / Decimal(series.cadence.approximateDays)
            }

        let baselineSpendTotal = stats.reduce(Decimal(0)) { $0 + $1.baselineSuggestion }
        let roundedIncome = Self.roundedToDollar(income)

        return Summary(
            months: boundaries.count,
            stats: stats,
            averageMonthlyIncome: roundedIncome,
            monthlyRecurringCommitments: Self.roundedToDollar(max(recurring, 0)),
            suggestedSavings: max(roundedIncome - baselineSpendTotal, 0),
            recentTransactions: Self.promptLines(for: transactions, limit: Self.promptTransactionLimit)
        )
    }

    /// Formats transactions as compact prompt lines for the AI — date, signed amount, category,
    /// merchant — most recent first, capped at `limit` with a note when older ones are dropped.
    /// Deliberately excludes account names, balances, notes, and receipts.
    static func promptLines(for transactions: [Transaction], limit: Int) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let sorted = transactions.sorted { $0.date > $1.date }
        var lines = sorted.prefix(limit).map { transaction in
            let category: String
            if transaction.isSplit {
                category = "Split (" + transaction.splits
                    .map { "\($0.category?.name ?? "Uncategorized"): \($0.amount)" }
                    .joined(separator: "; ") + ")"
            } else {
                category = transaction.category?.name ?? "Uncategorized"
            }
            return "\(formatter.string(from: transaction.date)) | \(transaction.amount) | \(category) | \(transaction.merchant)"
        }
        if sorted.count > limit {
            lines.append("… plus \(sorted.count - limit) earlier transactions not shown.")
        }
        return lines
    }

    /// Baseline: the average, tilted toward recent months when spending is clearly moving —
    /// a category that grew shouldn't get a budget it already exceeds every month.
    private static func baseline(average: Decimal, recentAverage: Decimal) -> Decimal {
        let blended = (average + recentAverage) / 2
        return roundedToDollar(blended)
    }

    private static func roundedToDollar(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }
}
