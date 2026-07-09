import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class RecurringViewModel {
    struct UpcomingCharge: Identifiable {
        let id: PersistentIdentifier
        let series: RecurringSeries
        let date: Date
    }

    private(set) var activeSeries: [RecurringSeries] = []
    private(set) var ignoredSeries: [RecurringSeries] = []
    private(set) var upcoming: [UpcomingCharge] = []
    private(set) var isDetecting = false

    /// Total of the next 30 days of expected charges (expenses only).
    private(set) var next30DaysOutflow: Decimal = 0

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load(runDetection: Bool = true) {
        if runDetection {
            isDetecting = true
            RecurringDetectionService(modelContext: modelContext).refresh()
            isDetecting = false
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
            if next <= horizon {
                charges.append(UpcomingCharge(id: series.persistentModelID, series: series, date: next))
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
