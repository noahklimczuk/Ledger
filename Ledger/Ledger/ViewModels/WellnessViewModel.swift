import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class WellnessViewModel {
    private(set) var result: WellnessResult = .empty
    /// A light 6-month savings-rate history (each value 0…1) for the trend chart.
    private(set) var trend: [Double] = []

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load() {
        result = WellnessScore.evaluate(modelContext: modelContext)
        trend = computeTrend()
    }

    /// Monthly (income − spending) / income over the last six months, clamped 0…1 — a simple,
    /// illustrative history of how much of each month's income was kept.
    private func computeTrend() -> [Double] {
        let calendar = Calendar.current
        let allTx = ((try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? [])
            .filter { $0.countsTowardTotals && !$0.isTransfer }
        let thisMonth = Budget.normalize(.now)

        var values: [Double] = []
        for offset in stride(from: 5, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .month, value: -offset, to: thisMonth),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { continue }
            let inMonth = allTx.filter { $0.date >= start && $0.date < end }
            let income = (inMonth.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount } as NSDecimalNumber).doubleValue
            let spend = (inMonth.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + (-$1.amount) } as NSDecimalNumber).doubleValue
            let rate = income > 0 ? (income - spend) / income : 0
            values.append(min(max(rate, 0), 1))
        }
        return values
    }
}
