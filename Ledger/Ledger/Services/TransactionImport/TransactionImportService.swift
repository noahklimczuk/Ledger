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
        let importedAccounts = try await source.fetchAccounts()

        for imported in importedAccounts {
            let account = try upsertAccount(imported, sourceIdentifier: source.sourceIdentifier, summary: &summary)
            // The user removed this linked account (archived). Don't revive it or pull new
            // transactions into it — that's the "deleted accounts come back on restart" bug.
            if account.isArchived { continue }
            let importedTransactions = try await source.fetchTransactions(accountExternalId: imported.id, since: since)
            for transaction in importedTransactions {
                if try insertTransactionIfNeeded(transaction, into: account, sourceKind: sourceKind) {
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
        for transaction in transactions {
            if try insertTransactionIfNeeded(transaction, into: account, sourceKind: sourceKind) {
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

    private func upsertAccount(_ imported: ImportedAccount, sourceIdentifier: String, summary: inout ImportSummary) throws -> Account {
        let externalAccountId = imported.id
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { account in
                account.externalAccountId == externalAccountId && account.externalSourceId == sourceIdentifier
            }
        )
        if let existing = try modelContext.fetch(descriptor).first {
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
        summary.accountsCreated += 1
        return account
    }

    /// Makes a linked account's displayed balance match what the institution actually reports.
    /// `currentBalance` is computed as `startingBalance + Σ(transactions)`, and imported history is
    /// often incomplete (Plaid caps how far back it returns), so we back-solve `startingBalance` from
    /// the reported balance and the transactions we do have. Liability accounts (credit) are stored
    /// negative so they reduce total balance / net worth. Runs on every sync, so the balance stays
    /// reconciled to reality.
    private func reconcileBalance(of account: Account, toReported reported: Decimal?) {
        guard let reported else { return }
        let signedReported = account.type.isLiability ? -reported : reported
        let transactionSum = account.transactions.reduce(Decimal(0)) { $0 + $1.amount }
        account.startingBalance = signedReported - transactionSum
    }

    private func insertTransactionIfNeeded(_ imported: ImportedTransaction, into account: Account, sourceKind: TransactionSourceKind) throws -> Bool {
        let externalId = imported.id
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.externalId == externalId })
        guard try modelContext.fetch(descriptor).first == nil else { return false }

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
