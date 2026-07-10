import Foundation
import SwiftData

/// Just-in-time budget alerts, run after every sync: a heads-up when a category crosses 80% of
/// its budget, an alert when it goes over, and a pace warning when overall spending is running
/// ahead of the calendar. Each threshold fires **once per category per month** (state kept in
/// UserDefaults), so the 5-minute sync loop never turns into notification spam.
///
/// Reuses `BudgetsViewModel` for the numbers so alerts always agree with the Budgets tab —
/// netted refunds, subcategory rollup, rollover and all.
@MainActor
struct BudgetGuardrailService {
    private struct State: Codable {
        var monthKey: String
        /// Category key → highest tier already notified (1 = approaching, 2 = over budget).
        var notifiedTiers: [String: Int] = [:]
        var lastPaceAlertAt: Date?
    }

    private static let stateKey = "budgetGuardrails.state"
    /// At most this many category alerts per run; anything beyond trickles out on later syncs
    /// instead of arriving as a burst the first time guardrails see an old over-spent month.
    private static let maxAlertsPerRun = 3
    /// How far ahead of the calendar (in budget share) overall spending must be to warn.
    private static let paceSlack = 0.15
    private static let paceAlertCooldown: TimeInterval = 4 * 24 * 60 * 60

    private let modelContext: ModelContext
    private let defaults = UserDefaults.standard

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func checkAndNotify() async {
        guard await NotificationService.ensureQuietAuthorization() else { return }

        let viewModel = BudgetsViewModel(modelContext: modelContext)
        viewModel.selectedMonth = Budget.normalize(.now)

        var state = loadState()
        state = await notifyCategoryCrossings(viewModel: viewModel, state: state)
        state = await notifyPace(viewModel: viewModel, state: state)
        saveState(state)
    }

    // MARK: - Category thresholds

    private func notifyCategoryCrossings(viewModel: BudgetsViewModel, state: State) async -> State {
        var state = state

        let candidates = viewModel.rows
            .compactMap { row -> (row: BudgetsViewModel.BudgetRow, name: String, key: String, tier: Int)? in
                guard let category = row.budget.category else { return nil }
                let tier = tier(for: row)
                guard tier > 0 else { return nil }
                let key = Self.key(for: category)
                guard tier > (state.notifiedTiers[key] ?? 0) else { return nil }
                return (row, category.name, key, tier)
            }
            // Worst first: overruns before warnings, then by how deep into the budget they are.
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return lhs.tier > rhs.tier }
                return (lhs.row.percentUsed ?? 0) > (rhs.row.percentUsed ?? 0)
            }
            .prefix(Self.maxAlertsPerRun)

        for candidate in candidates {
            await NotificationService.deliver(
                identifier: "guardrail.\(candidate.key).\(candidate.tier)",
                title: title(for: candidate),
                body: body(for: candidate.row, daysRemaining: viewModel.daysRemaining)
            )
            state.notifiedTiers[candidate.key] = candidate.tier
        }
        return state
    }

    private func tier(for row: BudgetsViewModel.BudgetRow) -> Int {
        if row.isOverBudget { return 2 }
        if let percent = row.percentUsed, percent >= 80 { return 1 }
        return 0
    }

    private func title(for candidate: (row: BudgetsViewModel.BudgetRow, name: String, key: String, tier: Int)) -> String {
        if candidate.tier == 2 {
            return "\(candidate.name) is over budget"
        }
        let percent = candidate.row.percentUsed.map { "\($0)%" } ?? "most"
        return "\(candidate.name) is at \(percent) of its budget"
    }

    private func body(for row: BudgetsViewModel.BudgetRow, daysRemaining: Int?) -> String {
        let spent = CurrencyFormatter.string(from: row.spent)
        let available = CurrencyFormatter.string(from: row.allocatedIncludingRollover)
        if row.isOverBudget {
            let over = CurrencyFormatter.string(from: -row.remaining)
            return "\(spent) spent of \(available) — \(over) over. New spending here comes out of another category."
        }
        let left = CurrencyFormatter.string(from: row.remaining)
        if let daysRemaining, daysRemaining > 0 {
            return "\(spent) spent of \(available). \(left) left for the next \(daysRemaining) day\(daysRemaining == 1 ? "" : "s")."
        }
        return "\(spent) spent of \(available) — \(left) left."
    }

    // MARK: - Pace

    private func notifyPace(viewModel: BudgetsViewModel, state: State) async -> State {
        var state = state

        // Meaningful only mid-month: too early and the numbers are noise, too late and the month
        // is already decided.
        guard viewModel.totalAvailable > 0,
              viewModel.monthProgress > 0.15, viewModel.monthProgress < 0.9,
              viewModel.overallProgress - viewModel.monthProgress >= Self.paceSlack else { return state }

        if let last = state.lastPaceAlertAt, Date().timeIntervalSince(last) < Self.paceAlertCooldown {
            return state
        }

        let spentPercent = Int(min(viewModel.overallProgress, 1.5) * 100)
        let monthPercent = Int(viewModel.monthProgress * 100)
        await NotificationService.deliver(
            identifier: "guardrail.pace",
            title: "Spending is ahead of pace",
            body: "\(spentPercent)% of this month's budget is used, but the month is only \(monthPercent)% done. A lighter week puts the plan back on track."
        )
        state.lastPaceAlertAt = Date()
        return state
    }

    // MARK: - State

    private func loadState() -> State {
        let currentKey = Self.monthKey(for: .now)
        guard let data = defaults.data(forKey: Self.stateKey),
              let stored = try? JSONDecoder().decode(State.self, from: data),
              stored.monthKey == currentKey else {
            return State(monthKey: currentKey)
        }
        return stored
    }

    private func saveState(_ state: State) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.stateKey)
        }
    }

    private static func monthKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }

    /// Stable per-category key for the notified-tier ledger. The persistent identifier survives
    /// renames; the name fallback only matters if encoding ever fails.
    private static func key(for category: Category) -> String {
        if let data = try? JSONEncoder().encode(category.persistentModelID) {
            return data.base64EncodedString()
        }
        return category.name
    }
}
