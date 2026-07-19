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

    /// Imports everything from `source`. The network fetch runs off-actor (it captures no context);
    /// the SwiftData upsert then runs synchronously here on the actor's background context, so its
    /// SQLite I/O stays off the main thread.
    @discardableResult
    func importAll(
        from source: TransactionSource,
        sourceKind: TransactionSourceKind,
        since: Date? = nil
    ) async throws -> TransactionImportService.ImportSummary {
        let fetched = try await TransactionImportService.fetchAll(from: source, since: since)
        return try TransactionImportService(modelContext: modelContext).importPrefetched(
            accounts: fetched.accounts,
            transactionsByAccount: fetched.transactionsByAccount,
            sourceIdentifier: source.sourceIdentifier,
            sourceKind: sourceKind
        )
    }

    /// Fills in categories for anything new (or newly matchable) and re-detects recurring series,
    /// on the same background context the import just wrote to.
    func categorizeAndDetectRecurring() {
        CategorizationService(modelContext: modelContext).categorizeAllUncategorized()
        // Back-fill debt links onto anything a rule now matches (e.g. a rule learned after these were
        // imported). Freshly imported rows already assigned + moved their balance during import, so
        // this pass links the rest without moving any money.
        DebtAssignmentService(modelContext: modelContext).assignAllUnassigned()
        RecurringDetectionService(modelContext: modelContext).refresh()
    }
}
