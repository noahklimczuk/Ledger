import Foundation
import SwiftData

/// Generates on-device insights from the user's own data — nothing leaves the device. Each detector
/// returns zero or more transient `Insight`s with deterministic ids so dismiss/snooze state
/// (`InsightState`) keeps applying across regenerations. The caller filters hidden ones and ranks.
@MainActor
struct InsightsEngine {
    let now: Date
    let calendar: Calendar
    let transactions: [Transaction]
    let currentMonthBudgets: [Budget]
    let recurringSeries: [RecurringSeries]
    private let categoryByID: [PersistentIdentifier: Category]

    init(
        now: Date = .now,
        calendar: Calendar = .current,
        transactions: [Transaction],
        categories: [Category],
        currentMonthBudgets: [Budget],
        recurringSeries: [RecurringSeries]
    ) {
        self.now = now
        self.calendar = calendar
        // Transfers between accounts aren't income or spending, so no detector should react to them.
        self.transactions = transactions.filter { !$0.isTransfer }
        self.currentMonthBudgets = currentMonthBudgets
        self.recurringSeries = recurringSeries
        self.categoryByID = Dictionary(categories.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func generate() -> [Insight] {
        var insights: [Insight] = []
        insights += trendingCategories()
        insights += budgetOvershoots()
        insights += duplicateSubscriptions()
        insights += forgottenSubscriptions()
        insights += largeTransactions()
        insights += leftoverCashComparison()
        return insights
    }

    // MARK: - Detectors

    /// Categories on pace to spend well above their recent 3-month average.
    private func trendingCategories() -> [Insight] {
        let monthStart = startOfMonth(now)
        let (daysInMonth, elapsed) = monthProgress()
        let current = categoryExpense(from: monthStart, to: addMonths(1, to: monthStart))
        let prior = categoryExpense(from: addMonths(-3, to: monthStart), to: monthStart)

        var results: [Insight] = []
        for (id, currentSpend) in current {
            guard let category = categoryByID[id], !category.isIncome else { continue }
            let priorAvg = (prior[id] ?? 0) / 3
            guard priorAvg >= 40 else { continue }

            let projected = double(currentSpend) * Double(daysInMonth) / Double(elapsed)
            let priorAvgD = double(priorAvg)
            guard projected >= priorAvgD * 1.4, projected - priorAvgD >= 40 else { continue }

            results.append(Insight(
                id: "trendingCategory:\(category.name):\(monthKey(now))",
                kind: .trendingCategory,
                title: "\(category.name) is trending up",
                message: "You're on pace for \(money(projected)) this month — about \(money(priorAvg)) is typical.",
                systemImage: "chart.line.uptrend.xyaxis",
                severity: .notable,
                rankValue: projected - priorAvgD
            ))
        }
        return results
    }

    /// Budgets projected to finish the month over their allocation.
    private func budgetOvershoots() -> [Insight] {
        let monthStart = startOfMonth(now)
        let (daysInMonth, elapsed) = monthProgress()
        let current = categoryExpense(from: monthStart, to: addMonths(1, to: monthStart))

        var results: [Insight] = []
        for budget in currentMonthBudgets {
            guard let category = budget.category, budget.allocatedAmount > 0 else { continue }
            let spent = current[category.persistentModelID] ?? 0
            let allocated = double(budget.allocatedAmount)
            let projected = double(spent) * Double(daysInMonth) / Double(elapsed)
            guard projected > allocated * 1.1 else { continue }

            let alreadyOver = double(spent) > allocated
            let message = alreadyOver
                ? "You've spent \(money(spent)) of your \(money(budget.allocatedAmount)) \(category.name) budget."
                : "At this pace you'll spend about \(money(projected)) — \(money(projected - allocated)) over your \(money(budget.allocatedAmount)) budget."
            results.append(Insight(
                id: "budgetOvershoot:\(category.name):\(monthKey(now))",
                kind: .budgetOvershoot,
                title: alreadyOver ? "\(category.name) is over budget" : "\(category.name) is on track to overspend",
                message: message,
                systemImage: "exclamationmark.triangle.fill",
                severity: alreadyOver ? .warning : .notable,
                rankValue: projected - allocated
            ))
        }
        return results
    }

    /// Two active recurring charges at the same cadence and near-identical amount — likely paying twice.
    private func duplicateSubscriptions() -> [Insight] {
        let subs = recurringSeries.filter { !$0.isIgnored && !$0.isIncome }
        var results: [Insight] = []
        var reported = Set<String>()

        for i in subs.indices {
            for j in subs.indices where j > i {
                let a = subs[i], b = subs[j]
                guard a.cadence == b.cadence else { continue }
                let amtA = abs(double(a.averageAmount)), amtB = abs(double(b.averageAmount))
                guard amtA >= 5, amtB >= 5 else { continue }
                guard abs(amtA - amtB) / max(amtA, amtB) <= 0.03 else { continue }

                let pairID = [a.merchantKey, b.merchantKey].sorted().joined(separator: "|")
                guard reported.insert(pairID).inserted else { continue }
                results.append(Insight(
                    id: "duplicateSubscription:\(pairID)",
                    kind: .duplicateSubscription,
                    title: "Possible duplicate subscription",
                    message: "\(a.displayName) and \(b.displayName) both charge about \(money(amtA)) \(a.cadence.displayName.lowercased()). Are you paying twice?",
                    systemImage: "doc.on.doc",
                    severity: .warning,
                    rankValue: amtA
                ))
            }
        }
        return results
    }

    /// The priciest active subscription, surfaced so the user can reconsider it.
    private func forgottenSubscriptions() -> [Insight] {
        let ranked = recurringSeries
            .filter { !$0.isIgnored && !$0.isIncome }
            .map { series -> (series: RecurringSeries, annual: Double) in
                (series, abs(double(series.averageAmount)) * 365.0 / Double(series.cadence.approximateDays))
            }
        guard let top = ranked.filter({ $0.annual >= 120 }).max(by: { $0.annual < $1.annual }) else { return [] }

        let series = top.series
        return [Insight(
            id: "forgottenSubscription:\(series.merchantKey)",
            kind: .forgottenSubscription,
            title: "Recurring charge worth a look",
            message: "\(series.displayName) costs about \(money(top.annual)) a year (\(money(abs(series.averageAmount))) \(series.cadence.displayName.lowercased())). Still using it?",
            systemImage: "arrow.triangle.2.circlepath",
            severity: .notable,
            rankValue: top.annual
        )]
    }

    /// Recent (last 30 days) purchases far above the user's typical transaction size.
    private func largeTransactions() -> [Insight] {
        let baselineStart = calendar.date(byAdding: .day, value: -180, to: now) ?? now
        let recentStart = calendar.date(byAdding: .day, value: -30, to: now) ?? now

        // Non-split expenses only — split transactions are deliberately itemized.
        let expenses = transactions.filter { $0.date >= baselineStart && $0.amount < 0 && !$0.isSplit }
        let magnitudes = expenses.map { abs(double($0.amount)) }.sorted()
        guard magnitudes.count >= 8 else { return [] }

        let median = magnitudes[magnitudes.count / 2]
        let threshold = max(200.0, median * 3)

        return expenses
            .filter { $0.date >= recentStart && abs(double($0.amount)) >= threshold }
            .sorted { abs(double($0.amount)) > abs(double($1.amount)) }
            .prefix(2)
            .map { transaction in
                Insight(
                    id: "largeTransaction:\(transaction.externalId ?? "\(transaction.merchant)-\(Int(transaction.date.timeIntervalSince1970))")",
                    kind: .largeTransaction,
                    title: "Unusually large purchase",
                    message: "\(money(abs(transaction.amount))) at \(transaction.merchant) on \(DateFormatting.medium(transaction.date)) is well above your usual spending.",
                    systemImage: "creditcard.trianglebadge.exclamationmark",
                    severity: .notable,
                    rankValue: double(abs(transaction.amount))
                )
            }
    }

    /// How much was left over (income − spending) last full month vs the month before.
    private func leftoverCashComparison() -> [Insight] {
        let currentMonthStart = startOfMonth(now)
        let lastMonthStart = addMonths(-1, to: currentMonthStart)
        let prevMonthStart = addMonths(-2, to: currentMonthStart)

        func net(from start: Date, to end: Date) -> Decimal {
            transactions.filter { $0.date >= start && $0.date < end }.reduce(Decimal(0)) { $0 + $1.amount }
        }
        func hasActivity(from start: Date, to end: Date) -> Bool {
            transactions.contains { $0.date >= start && $0.date < end }
        }
        guard hasActivity(from: lastMonthStart, to: currentMonthStart),
              hasActivity(from: prevMonthStart, to: lastMonthStart) else { return [] }

        let lastNet = net(from: lastMonthStart, to: currentMonthStart)
        let prevNet = net(from: prevMonthStart, to: lastMonthStart)
        let delta = lastNet - prevNet
        let deltaMag = abs(double(delta))
        guard deltaMag >= 100, deltaMag / max(abs(double(prevNet)), 1) >= 0.2 else { return [] }

        let improved = delta > 0
        return [Insight(
            id: "leftoverCash:\(monthKey(lastMonthStart))",
            kind: .leftoverCash,
            title: improved ? "You kept more last month" : "You kept less last month",
            message: "\(DateFormatting.monthYear(lastMonthStart)) left you \(money(lastNet)) after spending — \(improved ? "up" : "down") \(money(abs(delta))) from the month before.",
            systemImage: improved ? "arrow.up.right.circle" : "arrow.down.right.circle",
            severity: .info,
            rankValue: deltaMag
        )]
    }

    // MARK: - Helpers

    /// Split-aware expense magnitude per category over `[start, end)`, keyed by category id.
    private func categoryExpense(from start: Date, to end: Date) -> [PersistentIdentifier: Decimal] {
        var totals: [PersistentIdentifier: Decimal] = [:]
        for transaction in transactions where transaction.date >= start && transaction.date < end {
            if transaction.isSplit {
                for split in transaction.splits {
                    guard let category = split.category, split.amount < 0 else { continue }
                    totals[category.persistentModelID, default: 0] += -split.amount
                }
            } else {
                guard let category = transaction.category, transaction.amount < 0 else { continue }
                totals[category.persistentModelID, default: 0] += -transaction.amount
            }
        }
        return totals
    }

    private func monthProgress() -> (daysInMonth: Int, elapsed: Int) {
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let elapsed = max(calendar.component(.day, from: now), 1)
        return (daysInMonth, min(elapsed, daysInMonth))
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func addMonths(_ value: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: value, to: date) ?? date
    }

    private func monthKey(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private func double(_ decimal: Decimal) -> Double { (decimal as NSDecimalNumber).doubleValue }

    /// Whole-dollar currency string from a Double.
    private func money(_ value: Double) -> String { money(Decimal(value)) }

    private func money(_ value: Decimal) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        return CurrencyFormatter.string(from: rounded)
    }
}
