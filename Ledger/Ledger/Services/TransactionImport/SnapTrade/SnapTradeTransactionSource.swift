import Foundation

/// `TransactionSource` adapter over the SnapTrade REST API. Requires the user to have already
/// completed SnapTrade's Connection Portal flow (see `SnapTradeConnectSession` +
/// `IntegrationsViewModel`) so a userSecret exists in `SnapTradeCredentialStore`.
struct SnapTradeTransactionSource: TransactionSource {
    let sourceIdentifier = "snapTrade"

    private let client: SnapTradeAPIClient
    private let credentials: SnapTradeCredentials

    init(credentials: SnapTradeCredentials, client: SnapTradeAPIClient = SnapTradeAPIClient()) {
        self.credentials = credentials
        self.client = client
    }

    func fetchAccounts() async throws -> [ImportedAccount] {
        let accounts = try await client.listAccounts(credentials: credentials)
        return accounts.map { dto in
            ImportedAccount(
                id: dto.id,
                name: dto.name ?? dto.institutionName ?? "Wealthsimple Account",
                institutionName: dto.institutionName,
                type: .investment,
                currencyCode: dto.balance?.total?.currency ?? "CAD",
                currentBalance: dto.balance?.total?.amount ?? 0
            )
        }
    }

    func fetchTransactions(accountExternalId: String, since: Date?) async throws -> [ImportedTransaction] {
        let activities = try await client.listActivities(accountId: accountExternalId, since: since, credentials: credentials)

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardFormatter = ISO8601DateFormatter()

        func parseDate(_ string: String?) -> Date? {
            guard let string else { return nil }
            return fractionalFormatter.date(from: string) ?? standardFormatter.date(from: string)
        }

        return activities.compactMap { activity -> ImportedTransaction? in
            guard let amount = activity.amount else { return nil }
            let date = parseDate(activity.tradeDate) ?? parseDate(activity.settlementDate) ?? .now
            return ImportedTransaction(
                id: activity.id,
                accountExternalId: accountExternalId,
                date: date,
                merchant: activity.description ?? activity.type ?? "Wealthsimple transaction",
                amount: amount,
                currencyCode: activity.currency?.code ?? "CAD"
            )
        }
    }
}
