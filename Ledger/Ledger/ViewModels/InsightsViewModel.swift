import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class InsightsViewModel {
    private(set) var insights: [Insight] = []

    private let modelContext: ModelContext
    private let maxVisible = 5

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load() {
        let now = Date()

        // Keep recurring detection current so subscription insights work without visiting the
        // Recurring screen first. (This persists its own results.)
        RecurringDetectionService(modelContext: modelContext).refresh()

        let transactions = ((try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? [])
            .filter(\.countsTowardTotals)
        let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        let recurring = (try? modelContext.fetch(FetchDescriptor<RecurringSeries>())) ?? []

        let monthStart = Budget.normalize(now)
        let budgetDescriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.month == monthStart })
        let budgets = (try? modelContext.fetch(budgetDescriptor)) ?? []

        let engine = InsightsEngine(
            now: now,
            transactions: transactions,
            categories: categories,
            currentMonthBudgets: budgets,
            recurringSeries: recurring
        )

        let states = statesByID()
        insights = engine.generate()
            .filter { !(states[$0.id]?.isHidden(asOf: now) ?? false) }
            .sorted { lhs, rhs in
                lhs.severity != rhs.severity ? lhs.severity > rhs.severity : lhs.rankValue > rhs.rankValue
            }
            .prefix(maxVisible)
            .map { $0 }
    }

    func dismiss(_ insight: Insight) {
        upsertState(for: insight.id) { $0.isDismissed = true }
        load()
    }

    func snooze(_ insight: Insight, days: Int = 7) {
        let until = Calendar.current.date(byAdding: .day, value: days, to: Date())
        upsertState(for: insight.id) {
            $0.snoozedUntil = until
            $0.isDismissed = false
        }
        load()
    }

    // MARK: - InsightState persistence

    private func statesByID() -> [String: InsightState] {
        let all = (try? modelContext.fetch(FetchDescriptor<InsightState>())) ?? []
        return Dictionary(all.map { ($0.insightId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func upsertState(for id: String, _ mutate: (InsightState) -> Void) {
        let descriptor = FetchDescriptor<InsightState>(predicate: #Predicate { $0.insightId == id })
        if let existing = try? modelContext.fetch(descriptor).first {
            mutate(existing)
        } else {
            let state = InsightState(insightId: id)
            mutate(state)
            modelContext.insert(state)
        }
        try? modelContext.save()
    }
}
