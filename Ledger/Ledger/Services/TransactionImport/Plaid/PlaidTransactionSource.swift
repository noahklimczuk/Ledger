import Foundation

/// `TransactionSource` adapter over the Plaid REST API. Requires the user to have already
/// completed Plaid's Hosted Link flow (see `PlaidConnectSession` + `IntegrationsViewModel`) so an
/// `access_token` exists in `PlaidCredentialStore`.
///
/// This is the bank/cash-account path: Plaid links Wealthsimple's *depository* products
/// (Wealthsimple Cash, savings) plus any other Canadian bank the user connects.
struct PlaidTransactionSource: TransactionSource {
    let sourceIdentifier = "plaid"

    private let client: PlaidAPIClient
    private let credentials: PlaidCredentials

    /// How far back to pull when no `since` is supplied (Plaid caps history by product/plan).
    private let defaultLookbackDays = 730
    /// Plaid's max page size for /transactions/get is 500.
    private let pageSize = 500

    init(credentials: PlaidCredentials, client: PlaidAPIClient = PlaidAPIClient()) {
        self.credentials = credentials
        self.client = client
    }

    func fetchAccounts() async throws -> [ImportedAccount] {
        let response = try await client.accounts(credentials: credentials)
        return (response.accounts ?? []).map { dto in
            ImportedAccount(
                id: dto.accountId,
                name: dto.officialName ?? dto.name ?? "Wealthsimple Account",
                institutionName: nil,
                type: Self.accountType(plaidType: dto.type, subtype: dto.subtype),
                currencyCode: dto.balances?.isoCurrencyCode ?? "CAD",
                currentBalance: dto.balances?.current
            )
        }
    }

    func fetchTransactions(accountExternalId: String, since: Date?) async throws -> [ImportedTransaction] {
        let endDate = Date()
        let startDate = since ?? Calendar.current.date(byAdding: .day, value: -defaultLookbackDays, to: endDate) ?? endDate

        var collected: [PlaidDTO.Transaction] = []
        var offset = 0

        while true {
            let page = try await client.transactions(
                credentials: credentials,
                accountId: accountExternalId,
                startDate: startDate,
                endDate: endDate,
                offset: offset,
                count: pageSize
            )
            let batch = page.transactions ?? []
            collected.append(contentsOf: batch)

            let total = page.totalTransactions ?? collected.count
            offset += batch.count
            if batch.isEmpty || offset >= total { break }
        }

        return collected
            // The request is already scoped to this account via `account_ids`; keep the filter as
            // a safety net in case Plaid ignores the option.
            .filter { $0.accountId == nil || $0.accountId == accountExternalId }
            // Pending transactions get a *new* transaction_id once they post, so importing one now
            // leaves a duplicate behind that externalId dedup can never catch (and the pending
            // amount can still change). Skip them; the posted version arrives on a later sync.
            .filter { $0.pending != true }
            .compactMap { dto -> ImportedTransaction? in
                guard let plaidAmount = dto.amount else { return nil }
                return ImportedTransaction(
                    id: dto.transactionId,
                    accountExternalId: accountExternalId,
                    date: parseDate(dto.date) ?? parseDate(dto.authorizedDate) ?? .now,
                    merchant: dto.merchantName ?? dto.name ?? "Transaction",
                    // Plaid signs the opposite way from Ledger: Plaid positive = money OUT.
                    // Negate so Ledger's convention (negative = money out) holds.
                    amount: -plaidAmount,
                    currencyCode: dto.isoCurrencyCode ?? "CAD"
                )
            }
    }

    /// Maps Plaid's `type`/`subtype` onto Ledger's `AccountType`. Wealthsimple Cash comes back as
    /// `depository` (subtype `checking` or `cash management`); savings as `depository`/`savings`.
    private static func accountType(plaidType: String?, subtype: String?) -> AccountType {
        switch plaidType {
        case "credit":
            return .credit
        case "investment", "brokerage":
            return .investment
        case "depository":
            return subtype == "savings" ? .savings : .chequing
        default:
            return .chequing
        }
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
