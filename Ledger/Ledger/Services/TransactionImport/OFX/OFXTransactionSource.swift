import Foundation

/// `TransactionSource` over parsed OFX/QFX records. Like the CSV source, OFX statements don't
/// define which local account they belong to, so the user picks the target account and
/// `fetchAccounts()` is empty. Dedup uses the bank-provided FITID (namespaced by account token)
/// so it's stable and unique even across re-downloads.
struct OFXTransactionSource: TransactionSource {
    nonisolated let sourceIdentifier = "ofx"

    let records: [OFXRecord]
    let accountToken: String
    let currencyCode: String

    func fetchAccounts() async throws -> [ImportedAccount] { [] }

    func fetchTransactions(accountExternalId: String, since: Date?) async throws -> [ImportedTransaction] {
        map().compactMap(\.transaction)
    }

    func map() -> [ImportMappedRow] {
        records.enumerated().map { index, record in
            let transaction = ImportedTransaction(
                id: "ofx:\(accountToken):\(record.fitid)",
                accountExternalId: accountToken,
                date: record.date,
                merchant: record.merchant,
                amount: record.amount,
                currencyCode: currencyCode
            )
            return ImportMappedRow(id: index, transaction: transaction, error: nil)
        }
    }
}
