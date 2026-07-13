import Foundation
import SwiftData

/// Runs the pure-database, no-network stages of the app refresh off the main thread, on their own
/// background `ModelContext`, so those fetches and writes don't block the UI (Xcode's Thread
/// Performance Checker flags them as main-thread database I/O).
///
/// Each stage here is **synchronous**, so it stays on this actor's executor start to finish and
/// never touches the context off its owning thread. The network sync and the budget-guardrail check
/// deliberately stay on the main actor in `AppRefreshCoordinator`: the sync interleaves network
/// `await`s with writes to the main context, and the guardrail check reads the `@MainActor`
/// `BudgetsViewModel`.
///
/// A background context created this way does not autosave, so every stage saves explicitly. The UI
/// still reads the main context and reloads via `AppRefreshCoordinator.refreshCount`, picking up the
/// changes these stages commit to the shared store.
@ModelActor
actor RefreshDBWorker {
    /// Ensure the built-in category catalog is present (first launch / catalog upgrade) before the
    /// sync tries to categorize anything.
    func seedDefaults() {
        DefaultDataSeeder.seedIfNeeded(modelContext: modelContext)
        try? modelContext.save()
    }

    /// Categorize any uncategorized transactions (including whatever the sync just imported) and
    /// re-detect recurring series from the latest history.
    func categorizeAndDetect() {
        CategorizationService(modelContext: modelContext).categorizeAllUncategorized()
        RecurringDetectionService(modelContext: modelContext).refresh()
        try? modelContext.save()
    }
}
