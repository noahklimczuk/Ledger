import Foundation
import SwiftData

/// Pulls accounts + transactions from a `TransactionSource` and upserts them into SwiftData,
/// deduping accounts by (externalSourceId, externalAccountId) and transactions by externalId
/// so re-running a sync never creates duplicates.
@MainActor
final class TransactionImportService {
    struct ImportSummary {
        var accountsCreated = 0
        var transactionsCreated = 0
        var transactionsSkipped = 0
    }

    private let modelContext: ModelContext
    private lazy var categorizer = CategorizationService(modelContext: modelContext)

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func importAll(from source: TransactionSource, sourceKind: TransactionSourceKind, since: Date? = nil) async throws -> ImportSummary {
        var summary = ImportSummary()
        // Collapse any duplicate linked accounts a previous (buggy) sync created, before matching
        // this run's accounts against the store. Persist the merge so the lookup below is built
        // from a store that no longer contains the removed duplicates.
        if deduplicateLinkedAccounts() > 0 {
            try? modelContext.save()
        }

        let importedAccounts = try await source.fetchAccounts()
        // One dedup-set fetch for the whole run — a sync of hundreds of rows shouldn't do a
        // store-wide fetch per row.
        var knownExternalIds = existingExternalIds()
        // Match incoming accounts against existing ones in memory, keyed by external id. A
        // SwiftData `#Predicate` on the optional external-id columns proved unreliable and let a
        // fresh linked account be created on every sync — the "duplicate accounts" bug.
        var linkedAccounts = existingLinkedAccounts(sourceIdentifier: source.sourceIdentifier)

        for imported in importedAccounts {
            let account = upsertAccount(imported, sourceIdentifier: source.sourceIdentifier, lookup: &linkedAccounts, summary: &summary)
            // The user removed this linked account (archived). Don't revive it or pull new
            // transactions into it — that's the "deleted accounts come back on restart" bug.
            if account.isArchived { continue }
            let importedTransactions = try await source.fetchTransactions(accountExternalId: imported.id, since: since)
            for transaction in importedTransactions {
                if insertTransactionIfNeeded(transaction, into: account, sourceKind: sourceKind, knownExternalIds: &knownExternalIds) {
                    summary.transactionsCreated += 1
                } else {
                    summary.transactionsSkipped += 1
                }
            }
            reconcileBalance(of: account, toReported: imported.currentBalance)
        }

        try modelContext.save()
        return summary
    }

    /// Imports a pre-mapped batch into a caller-chosen account (used by CSV/OFX file import,
    /// where the account isn't defined by the source). Reuses the same externalId dedup as sync.
    @discardableResult
    func importTransactions(_ transactions: [ImportedTransaction], into account: Account, sourceKind: TransactionSourceKind) throws -> ImportSummary {
        var summary = ImportSummary()
        var knownExternalIds = existingExternalIds()
        for transaction in transactions {
            if insertTransactionIfNeeded(transaction, into: account, sourceKind: sourceKind, knownExternalIds: &knownExternalIds) {
                summary.transactionsCreated += 1
            } else {
                summary.transactionsSkipped += 1
            }
        }
        try modelContext.save()
        return summary
    }

    /// The set of externalIds already in the store, so an import preview can flag which rows
    /// are duplicates before anything is written.
    func existingExternalIds() -> Set<String> {
        let all = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        return Set(all.compactMap(\.externalId))
    }

    /// Merges duplicate linked accounts and persists the result, independently of a sync.
    /// Called on every app refresh so the cleanup runs even when the linked connection is
    /// disconnected or failing to sync (in which case `importAll` never runs). Returns the number
    /// of duplicate accounts removed.
    @discardableResult
    func mergeDuplicateLinkedAccounts() -> Int {
        let removed = deduplicateLinkedAccounts()
        if removed > 0 {
            try? modelContext.save()
        }
        return removed
    }

    /// Existing linked accounts for this source, keyed by their external account id. Matched in
    /// memory rather than via a `#Predicate` on the optional external-id columns, which SwiftData
    /// evaluated unreliably (and so kept minting duplicate accounts).
    private func existingLinkedAccounts(sourceIdentifier: String) -> [String: Account] {
        let all = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        var map: [String: Account] = [:]
        for account in all {
            guard account.externalSourceId == sourceIdentifier, let externalId = account.externalAccountId else { continue }
            // deduplicateLinkedAccounts ran first, so there's at most one per id; keep the first regardless.
            if map[externalId] == nil { map[externalId] = account }
        }
        return map
    }

    private func upsertAccount(
        _ imported: ImportedAccount,
        sourceIdentifier: String,
        lookup: inout [String: Account],
        summary: inout ImportSummary
    ) -> Account {
        if let existing = lookup[imported.id] {
            // Conflict handling: a re-sync must not clobber a manual rename of a linked account,
            // so leave name/institution as the user last left them.
            return existing
        }

        let account = Account(
            name: imported.name,
            type: imported.type,
            institutionName: imported.institutionName,
            currencyCode: imported.currencyCode,
            startingBalance: 0,
            externalSourceId: sourceIdentifier,
            externalAccountId: imported.id
        )
        modelContext.insert(account)
        lookup[imported.id] = account
        summary.accountsCreated += 1
        return account
    }

    /// Merges duplicate linked accounts that share the same `(externalSourceId, externalAccountId)`
    /// — the mess left by the old predicate bug. Keeps one canonical account (the one holding the
    /// most transactions, then the earliest created), moves any stray transactions onto it, and
    /// deletes the redundant copies so balances and net worth stop double-counting.
    /// Returns the number of duplicate accounts removed.
    @discardableResult
    private func deduplicateLinkedAccounts() -> Int {
        let all = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []

        var groups: [String: [Account]] = [:]
        for account in all {
            guard let source = account.externalSourceId, let externalId = account.externalAccountId else { continue }
            groups["\(source)\u{1}\(externalId)", default: []].append(account)
        }

        var removed = 0
        for accounts in groups.values where accounts.count > 1 {
            let ordered = accounts.sorted {
                $0.transactions.count != $1.transactions.count
                    ? $0.transactions.count > $1.transactions.count
                    : $0.createdAt < $1.createdAt
            }
            let canonical = ordered[0]
            var canonicalExternalIds = Set(canonical.transactions.compactMap(\.externalId))

            for duplicate in ordered.dropFirst() {
                for transaction in Array(duplicate.transactions) {
                    if let externalId = transaction.externalId, !canonicalExternalIds.insert(externalId).inserted {
                        // Canonical already holds this transaction — drop the duplicate copy.
                        modelContext.delete(transaction)
                    } else {
                        transaction.account = canonical
                    }
                }
                modelContext.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }

    /// Makes a linked account's displayed balance match what the institution actually reports.
    /// `currentBalance` is computed as `startingBalance + Σ(transactions)`, and imported history is
    /// often incomplete (the sync caps how far back it returns), so we back-solve `startingBalance` from
    /// the reported balance and the transactions we do have. Liability accounts (credit) are stored
    /// negative so they reduce total balance / net worth. Runs on every sync, so the balance stays
    /// reconciled to reality.
    private func reconcileBalance(of account: Account, toReported reported: Decimal?) {
        guard let reported else { return }
        let signedReported = account.type.isLiability ? -reported : reported
        let transactionSum = account.transactions.reduce(Decimal(0)) { $0 + $1.amount }
        account.startingBalance = signedReported - transactionSum
    }

    /// Inserts unless `knownExternalIds` already contains the id; records the id either way so a
    /// duplicate later in the same batch is also skipped.
    private func insertTransactionIfNeeded(
        _ imported: ImportedTransaction,
        into account: Account,
        sourceKind: TransactionSourceKind,
        knownExternalIds: inout Set<String>
    ) -> Bool {
        guard knownExternalIds.insert(imported.id).inserted else { return false }

        let transaction = Transaction(
            date: imported.date,
            merchant: imported.merchant,
            amount: imported.amount,
            account: account,
            sourceKind: sourceKind,
            externalId: imported.id
        )
        modelContext.insert(transaction)
        // Replay learned merchant → category rules onto freshly imported transactions.
        categorizer.applyRule(to: transaction)
        return true
    }
}
