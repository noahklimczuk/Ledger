import Foundation
import Observation
import SwiftData

/// Runs the app-wide refresh: pull the latest balances/transactions from the linked connection,
/// auto-categorize anything new, and re-detect recurring series. Centralized so launch, every
/// foreground, the periodic in-app timer, and pull-to-refresh all go through the same path, with
/// an in-flight guard so overlapping triggers don't kick off two syncs at once.
///
/// It's `@Observable` and injected into the environment so screens can reload their (manually
/// fetched) data once a background refresh finishes: they observe `refreshCount`, which bumps after
/// every completed refresh. Without this, a tab that already loaded once would keep showing stale
/// data until the user re-navigated.
@MainActor
@Observable
final class AppRefreshCoordinator {
    /// Increments after each completed refresh. Views key off this to re-fetch from SwiftData.
    private(set) var refreshCount = 0
    private(set) var lastRefreshedAt: Date?
    private(set) var isRefreshing = false

    /// How often to re-sync while the app stays in the foreground. Foreground-only sync means a
    /// user who leaves the app open would otherwise never see new bank transactions.
    private static let periodicInterval: TimeInterval = 5 * 60

    @ObservationIgnored private var periodicTask: Task<Void, Never>?

    func refresh(container: ModelContainer) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let context = container.mainContext
        DefaultDataSeeder.seedIfNeeded(modelContext: context)

        let coordinator = PlaidSyncCoordinator()
        if coordinator.isConnected {
            await coordinator.sync(modelContext: context)
        }

        // Fill in categories for anything new (or newly matchable), then refresh recurring series.
        CategorizationService(modelContext: context).categorizeAllUncategorized()
        RecurringDetectionService(modelContext: context).refresh()

        // With the freshest numbers in hand, fire any budget guardrail alerts (80% / over /
        // ahead-of-pace) that newly imported spending just tripped.
        await BudgetGuardrailService(modelContext: context).checkAndNotify()

        lastRefreshedAt = .now
        refreshCount += 1
    }

    /// Keeps data fresh while the app stays open by re-running `refresh` on an interval. Call on
    /// scene-active and pair with `stopPeriodicRefresh()` on background — there's no point (and no
    /// runtime) polling while suspended.
    func startPeriodicRefresh(container: ModelContainer) {
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.periodicInterval))
                guard !Task.isCancelled else { return }
                await self?.refresh(container: container)
            }
        }
    }

    func stopPeriodicRefresh() {
        periodicTask?.cancel()
        periodicTask = nil
    }
}
