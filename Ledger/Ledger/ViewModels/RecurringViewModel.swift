import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class RecurringViewModel {
    struct UpcomingCharge: Identifiable {
        /// Series id + occurrence date: one series can now appear several times in the forecast
        /// (a weekly charge shows every expected hit, not just the next one).
        let id: String
        let series: RecurringSeries
        let date: Date
    }

    private(set) var activeSeries: [RecurringSeries] = []
    private(set) var ignoredSeries: [RecurringSeries] = []
    private(set) var upcoming: [UpcomingCharge] = []

    /// Recurring income streams (paycheques, interest, regular deposits), grouped for display.
    var incomeSeries: [RecurringSeries] { activeSeries.filter(\.isIncome) }
    /// Regular payments — subscriptions and bills that go out on a cadence.
    var expenseSeries: [RecurringSeries] { activeSeries.filter { !$0.isIncome } }

    /// Total of the next 30 days of expected recurring income.
    var next30DaysIncome: Decimal {
        let thirtyDays = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
        return upcoming
            .filter { $0.date <= thirtyDays && $0.series.averageAmount > 0 }
            .reduce(Decimal(0)) { $0 + $1.series.averageAmount }
    }

    /// Total of the next 30 days of expected charges (expenses only).
    private(set) var next30DaysOutflow: Decimal = 0

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load(runDetection: Bool = true) {
        if runDetection {
            RecurringDetectionService(modelContext: modelContext).refresh()
        }

        let all = (try? modelContext.fetch(FetchDescriptor<RecurringSeries>(
            sortBy: [SortDescriptor(\.nextExpected)]
        ))) ?? []

        activeSeries = all.filter { !$0.isIgnored }
        ignoredSeries = all.filter { $0.isIgnored }
        buildForecast()
    }

    private func buildForecast() {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: 60, to: .now) ?? .now
        let thirtyDays = calendar.date(byAdding: .day, value: 30, to: .now) ?? .now

        var charges: [UpcomingCharge] = []
        for series in activeSeries {
            // Roll the next-expected date forward if it's already in the past, so forecasting
            // stays meaningful even if detection hasn't run in a while.
            var next = series.nextExpected
            var guardCounter = 0
            while next < calendar.startOfDay(for: .now) && guardCounter < 24 {
                next = series.cadence.nextDate(after: next)
                guardCounter += 1
            }
            // Every expected occurrence inside the horizon, not just the first — a weekly charge
            // hits ~9 times in 60 days and the outflow totals below must reflect that.
            var occurrenceCount = 0
            while next <= horizon && occurrenceCount < 24 {
                charges.append(UpcomingCharge(
                    id: "\(series.merchantKey)|\(next.timeIntervalSince1970)",
                    series: series,
                    date: next
                ))
                next = series.cadence.nextDate(after: next)
                occurrenceCount += 1
            }
        }

        upcoming = charges.sorted { $0.date < $1.date }
        next30DaysOutflow = upcoming
            .filter { $0.date <= thirtyDays && $0.series.averageAmount < 0 }
            .reduce(Decimal(0)) { $0 + (-$1.series.averageAmount) }
    }

    func setIgnored(_ series: RecurringSeries, ignored: Bool) {
        series.isIgnored = ignored
        try? modelContext.save()
        load(runDetection: false)
    }
}
