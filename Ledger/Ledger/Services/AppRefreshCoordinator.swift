import Foundation
import Observation
import SwiftData

/// Runs the "every time the app opens" refresh: pull the latest balances/transactions from the
/// linked connection, auto-categorize anything new, and re-detect recurring series. Centralized so
/// launch and every foreground go through the same path, with an in-flight guard so overlapping
/// scene-phase changes don't kick off two syncs at once.
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

    func refreshOnForeground(container: ModelContainer) async {
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

        lastRefreshedAt = .now
        refreshCount += 1
    }
}
