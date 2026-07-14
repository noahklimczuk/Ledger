import Foundation

struct ImportedAccount: Sendable, Identifiable {
    var id: String
    var name: String
    var institutionName: String?
    var type: AccountType
    var currencyCode: String
    /// The balance the institution reports, if available. Nil when the source can't provide one
    /// (so the caller leaves the derived balance alone rather than reconciling to a bogus value).
    var currentBalance: Decimal?
}

struct ImportedTransaction: Sendable, Identifiable {
    var id: String
    var accountExternalId: String
    var date: Date
    var merchant: String
    var amount: Decimal
    var currencyCode: String
}

/// Anything that can hand the app a batch of accounts/transactions from outside SwiftData.
///
/// Manual entry does **not** go through this protocol -- it writes directly to SwiftData via
/// `TransactionEditViewModel`. This protocol exists purely for bulk/external ingestion: CSV/OFX
/// import and Wealthsimple (bank/cash accounts) today, with room for another source to slot in later
/// behind the same interface without touching any call sites.
protocol TransactionSource: Sendable {
    // nonisolated so the off-main import (TransactionImportService, on a background context) can read
    // it synchronously — the project defaults types to @MainActor. The async fetch methods stay
    // main-actor: awaiting them from the background context hops for the network call, which is fine.
    nonisolated var sourceIdentifier: String { get }
    func fetchAccounts() async throws -> [ImportedAccount]
    func fetchTransactions(accountExternalId: String, since: Date?) async throws -> [ImportedTransaction]
}
