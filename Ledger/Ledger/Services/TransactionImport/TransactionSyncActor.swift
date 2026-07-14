import Foundation
import SwiftData

/// Runs the SwiftData-heavy part of a refresh off the main thread.
///
/// SwiftData's `mainContext` does its SQLite work synchronously on the main actor, so importing a
/// batch of bank transactions there stutters the UI — Xcode's Thread Performance Checker flags it as
/// "Performing I/O on the main thread can cause hangs," pointing at `TransactionImportService`. A
/// `@ModelActor` gives us a private `ModelContext` on a background executor; the same context-driven
/// services (import, categorization, recurring detection) run there instead. Their saves persist to
/// the shared store, and the UI's `mainContext` picks the rows up on its next fetch — which the
/// post-refresh `refreshCount` bump already triggers across the app's screens.
///
/// One actor instance per refresh means dedup, import, and categorization all share a single
/// background context, so categorization sees exactly what the import just wrote.
@ModelActor
actor TransactionSyncActor {
    /// Collapses duplicate linked accounts and persists the result, on the background context.
    @discardableResult
    func mergeDuplicateLinkedAccounts() -> Int {
        TransactionImportService(modelContext: modelContext).mergeDuplicateLinkedAccounts()
    }

    /// Imports everything from `source` (network fetch + upsert) on the background context.
    @discardableResult
    func importAll(
        from source: TransactionSource,
        sourceKind: TransactionSourceKind,
        since: Date? = nil
    ) async throws -> TransactionImportService.ImportSummary {
        try await TransactionImportService(modelContext: modelContext)
            .importAll(from: source, sourceKind: sourceKind, since: since)
    }

    /// Fills in categories for anything new (or newly matchable) and re-detects recurring series,
    /// on the same background context the import just wrote to.
    func categorizeAndDetectRecurring() {
        CategorizationService(modelContext: modelContext).categorizeAllUncategorized()
        RecurringDetectionService(modelContext: modelContext).refresh()
    }
}
