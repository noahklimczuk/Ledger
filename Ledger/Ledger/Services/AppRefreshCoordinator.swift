import Foundation
import SwiftData

/// Runs the "every time the app opens" refresh: pull the latest balances/transactions from the
/// linked connection, auto-categorize anything new, and re-detect recurring series. Centralized so
/// launch and every foreground go through the same path, with an in-flight guard so overlapping
/// scene-phase changes don't kick off two syncs at once.
@MainActor
enum AppRefreshCoordinator {
    private static var isRefreshing = false

    /// Full refresh on foreground: seed defaults if needed, sync the linked connection, then
    /// categorize and re-detect recurring. Unlike the old throttled auto-sync, this runs on every
    /// open so new transactions/balances show up right away.
    static func refreshOnForeground(container: ModelContainer) async {
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
    }
}
