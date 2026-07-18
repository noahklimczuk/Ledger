import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class RecurringViewModel {
    struct UpcomingCharge: Identifiable {
        /// Series key + occurrence date: one series can appear several times in the forecast
        /// (a weekly charge shows every expected hit, not just the next one).
        let id: String
        let series: RecurringSeries
        let date: Date
        /// What the charge is predicted to be — the latest observed amount, reflecting price changes.
        let amount: Decimal
    }

    /// A smart, actionable signal about the user's recurring money — the "needs attention" layer.
    struct Insight: Identifiable {
        enum Kind { case needsReview, likelyCancelled, priceIncrease, priceDecrease, dueThisWeek }
        let id: String
        let kind: Kind
        let title: String
        let detail: String
        /// The series to open when tapped; nil for aggregate insights (e.g. "3 to review").
        let series: RecurringSeries?
    }

    // Sections
    private(set) var allSeries: [RecurringSeries] = []
    private(set) var upcoming: [UpcomingCharge] = []
    private(set) var insights: [Insight] = []

    /// Live subscriptions/bills going out on a cadence.
    var activeExpenses: [RecurringSeries] {
        allSeries.filter { $0.status == .active && !$0.isIncome }
            .sorted { $0.nextExpected < $1.nextExpected }
    }
    /// Live recurring income (paycheques, interest, regular deposits).
    var incomeSeries: [RecurringSeries] {
        allSeries.filter { $0.status == .active && $0.isIncome }
            .sorted { $0.nextExpected < $1.nextExpected }
    }
    /// Detections not confident enough to trust yet — the user confirms or dismisses these.
    var suggestedSeries: [RecurringSeries] {
        allSeries.filter { $0.status == .suggested }
            .sorted { $0.detectionConfidence > $1.detectionConfidence }
    }
    /// Series that stopped charging past their cadence — likely cancelled.
    var endedSeries: [RecurringSeries] {
        allSeries.filter { $0.status == .ended }
            .sorted { $0.lastOccurrence > $1.lastOccurrence }
    }
    var pausedSeries: [RecurringSeries] {
        allSeries.filter { $0.status == .paused }
    }
    var ignoredSeries: [RecurringSeries] {
        allSeries.filter { $0.status == .ignored }
    }

    var hasAnySeries: Bool { !allSeries.isEmpty }

    // MARK: - Totals

    /// Monthly-equivalent spend across live subscriptions (cadence-normalized).
    var monthlyRecurringExpense: Decimal {
        activeExpenses.reduce(Decimal(0)) { $0 + $1.monthlyEquivalent }
    }
    var annualRecurringExpense: Decimal { monthlyRecurringExpense * 12 }

    /// Monthly-equivalent recurring income.
    var monthlyRecurringIncome: Decimal {
        incomeSeries.reduce(Decimal(0)) { $0 + $1.monthlyEquivalent }
    }

    /// Net recurring cash flow per month (income minus subscriptions).
    var netMonthly: Decimal { monthlyRecurringIncome - monthlyRecurringExpense }

    var activeSubscriptionCount: Int { activeExpenses.count }

    /// Expected recurring outflow over the next 30 days (every hit, not just the first).
    private(set) var next30DaysOutflow: Decimal = 0
    /// Expected recurring income over the next 30 days.
    private(set) var next30DaysIncome: Decimal = 0

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load(runDetection: Bool = true, now: Date = .now) {
        if runDetection {
            RecurringDetectionService(modelContext: modelContext).refresh(now: now)
        }

        allSeries = (try? modelContext.fetch(FetchDescriptor<RecurringSeries>(
            sortBy: [SortDescriptor(\.nextExpected)]
        ))) ?? []

        buildForecast(now: now)
        buildInsights(now: now)
    }

    private func buildForecast(now: Date) {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: 60, to: now) ?? now
        let thirtyDays = calendar.date(byAdding: .day, value: 30, to: now) ?? now
        let live = allSeries.filter { $0.status == .active }

        var charges: [UpcomingCharge] = []
        for series in live {
            // Roll a stale next-expected forward so forecasting stays meaningful even if the series
            // hasn't been re-detected in a while.
            var next = series.nextExpected
            var guardCounter = 0
            while next < calendar.startOfDay(for: now) && guardCounter < 24 {
                next = series.cadence.nextDate(after: next)
                guardCounter += 1
            }
            var occurrenceCount = 0
            while next <= horizon && occurrenceCount < 24 {
                charges.append(UpcomingCharge(
                    id: "\(series.merchantKey)|\(next.timeIntervalSince1970)",
                    series: series,
                    date: next,
                    amount: series.predictedAmount
                ))
                next = series.cadence.nextDate(after: next)
                occurrenceCount += 1
            }
        }

        upcoming = charges.sorted { $0.date < $1.date }
        next30DaysOutflow = upcoming
            .filter { $0.date <= thirtyDays && $0.amount < 0 }
            .reduce(Decimal(0)) { $0 + (-$1.amount) }
        next30DaysIncome = upcoming
            .filter { $0.date <= thirtyDays && $0.amount > 0 }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private func buildInsights(now: Date) {
        var result: [Insight] = []

        // Suggestions awaiting review.
        let suggestedCount = suggestedSeries.count
        if suggestedCount > 0 {
            result.append(Insight(
                id: "needsReview",
                kind: .needsReview,
                title: "\(suggestedCount) to review",
                detail: "Possible recurring \(suggestedCount == 1 ? "charge" : "charges") Ledger isn't sure about yet.",
                series: nil
            ))
        }

        // Likely-cancelled subscriptions (stopped charging).
        for series in endedSeries where !series.isIncome {
            let days = series.daysOverdue(asOf: now)
            result.append(Insight(
                id: "ended-\(series.merchantKey)",
                kind: .likelyCancelled,
                title: "\(series.displayName) looks cancelled",
                detail: days > 0 ? "No charge in \(days) days — remove it if you cancelled." : "Hasn't charged on schedule.",
                series: series
            ))
        }

        // Price changes on live/suggested series.
        for series in allSeries where series.status == .active || series.status == .suggested {
            guard let change = series.priceChange else { continue }
            let pct = Int((abs(change.fraction) * 100).rounded())
            result.append(Insight(
                id: "price-\(series.merchantKey)",
                kind: change.isIncrease ? .priceIncrease : .priceDecrease,
                title: "\(series.displayName) \(change.isIncrease ? "went up" : "went down")",
                detail: "\(CurrencyFormatter.string(from: change.previous)) → \(CurrencyFormatter.string(from: change.current)) (\(pct)%)",
                series: series
            ))
        }

        // Money going out this week.
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let dueSoon = upcoming.filter { $0.date <= weekEnd && $0.amount < 0 }
        let dueSoonTotal = dueSoon.reduce(Decimal(0)) { $0 + (-$1.amount) }
        if dueSoonTotal > 0 {
            result.append(Insight(
                id: "dueThisWeek",
                kind: .dueThisWeek,
                title: "\(CurrencyFormatter.string(from: dueSoonTotal)) due this week",
                detail: "\(dueSoon.count) recurring \(dueSoon.count == 1 ? "charge" : "charges") in the next 7 days.",
                series: nil
            ))
        }

        insights = result
    }

    // MARK: - Lifecycle actions

    /// Confirm a suggested detection as a real, active series.
    func confirm(_ series: RecurringSeries) { setStatus(series, .active) }
    /// Pause a live series (keeps it, drops it from totals/forecast).
    func pause(_ series: RecurringSeries) { setStatus(series, .paused) }
    /// Resume a paused series.
    func resume(_ series: RecurringSeries) { setStatus(series, .active) }
    /// Mark a series ended/cancelled.
    func markEnded(_ series: RecurringSeries) { setStatus(series, .ended) }
    /// Bring an ended series back to active (it started charging again).
    func reactivate(_ series: RecurringSeries) { setStatus(series, .active) }

    /// Dismiss a series entirely (hidden from everything).
    func ignore(_ series: RecurringSeries) {
        series.isIgnored = true
        series.statusRaw = RecurringStatus.ignored.rawValue
        persist()
    }

    /// Restore a dismissed series to active.
    func restore(_ series: RecurringSeries) {
        series.isIgnored = false
        series.statusRaw = RecurringStatus.active.rawValue
        persist()
    }

    private func setStatus(_ series: RecurringSeries, _ status: RecurringStatus) {
        series.isIgnored = (status == .ignored)
        series.statusRaw = status.rawValue
        series.updatedAt = .now
        persist()
    }

    private func persist() {
        try? modelContext.save()
        // Reload without re-running detection so the user's just-made choice isn't reconciled away.
        load(runDetection: false)
    }
}
