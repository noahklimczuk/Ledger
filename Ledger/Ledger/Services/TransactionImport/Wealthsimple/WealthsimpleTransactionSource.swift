import Foundation

/// `TransactionSource` adapter over Wealthsimple's own API. This is the bank/cash path -- it pulls
/// the user's **Wealthsimple Cash** account(s) and their activity feed, mapped into Ledger's model.
///
/// Requires an authenticated `WealthsimpleSession` (see `WealthsimpleAPIClient.logIn`) and the
/// resolved `identityId`. Sync itself is driven by `WealthsimpleSyncCoordinator`.
struct WealthsimpleTransactionSource: TransactionSource {
    nonisolated let sourceIdentifier = "wealthsimple"

    private let client: WealthsimpleAPIClient
    private let session: WealthsimpleSession
    private let identityId: String

    /// How far back to pull when no `since` is supplied.
    private let defaultLookbackDays = 730
    /// Activity feed page size.
    private let pageSize = 100

    init(client: WealthsimpleAPIClient, session: WealthsimpleSession, identityId: String) {
        self.client = client
        self.session = session
        self.identityId = identityId
    }

    func fetchAccounts() async throws -> [ImportedAccount] {
        let data = try await client.query(
            WealthsimpleDTO.AccountsData.self,
            operationName: "FetchAccounts",
            query: Self.accountsQuery,
            variables: ["identityId": identityId, "pageSize": 25],
            session: session
        )
        let nodes = (data.identity?.accounts?.edges ?? []).compactMap(\.node)
        return nodes.compactMap(Self.mapAccount)
    }

    func fetchTransactions(accountExternalId: String, since: Date?) async throws -> [ImportedTransaction] {
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let startDate = since ?? Calendar.current.date(byAdding: .day, value: -defaultLookbackDays, to: endDate) ?? endDate

        var collected: [ImportedTransaction] = []
        var cursor: String?

        // Paginate the activity feed until there are no more pages. `first`/`after` cursors mirror
        // the web app; we stop as soon as Wealthsimple says there's no next page.
        repeat {
            let condition: [String: Any] = [
                "accountIds": [accountExternalId],
                "startDate": Self.dateOnly(startDate),
                "endDate": Self.dateOnly(endDate)
            ]

            var variables: [String: Any] = [
                "first": pageSize,
                "condition": condition,
                "orderBy": "OCCURRED_AT_DESC"
            ]
            if let cursor { variables["cursor"] = cursor }

            let data = try await client.query(
                WealthsimpleDTO.ActivitiesData.self,
                operationName: "FetchActivityFeedItems",
                query: Self.activitiesQuery,
                variables: variables,
                session: session
            )

            let feed = data.activityFeedItems
            let nodes = (feed?.edges ?? []).compactMap(\.node)
            collected.append(contentsOf: nodes.compactMap { Self.mapActivity($0, accountExternalId: accountExternalId) })

            if feed?.pageInfo?.hasNextPage == true, let next = feed?.pageInfo?.endCursor {
                cursor = next
            } else {
                cursor = nil
            }
        } while cursor != nil

        return collected
    }

    // MARK: - Mapping (pure, unit-tested)

    /// Cash is the only depository ("bank") product Wealthsimple offers; everything else
    /// (registered/managed/crypto) is an investment account we deliberately skip on this screen.
    static func mapAccount(_ node: WealthsimpleDTO.AccountNode) -> ImportedAccount? {
        guard let id = node.id, node.unifiedAccountType == "CASH" else { return nil }
        // Skip closed accounts so a stale account isn't re-created after the user archives it.
        if let status = node.status, status != "open" { return nil }

        return ImportedAccount(
            id: id,
            name: node.nickname?.isEmpty == false ? node.nickname! : "Wealthsimple Cash",
            institutionName: "Wealthsimple",
            type: .chequing,
            currencyCode: node.currency ?? "CAD",
            currentBalance: node.financials?.currentCombined?.netLiquidationValue?.amount.flatMap { Decimal(string: $0) }
        )
    }

    /// Maps one activity-feed row to an `ImportedTransaction`, or nil if it should be skipped
    /// (no amount, or a non-final status that would re-post under a new id later).
    static func mapActivity(_ node: WealthsimpleDTO.ActivityNode, accountExternalId: String) -> ImportedTransaction? {
        guard let id = node.canonicalId, let amountString = node.amount, let magnitude = Decimal(string: amountString) else {
            return nil
        }
        // Rejected/cancelled/expired activities never settle; skip them. Legacy transfer rows are
        // bookkeeping duplicates of a paired activity, so drop them too (matches the ws-api clients).
        let status = (node.status ?? "").lowercased()
        if ["rejected", "cancelled", "expired"].contains(status) { return nil }
        if node.type == "LEGACY_TRANSFER" { return nil }

        // Direction comes from `amountSign` (money out = "negative"), matching Ledger's own
        // convention. Be tolerant of casing and of an already-signed amount string, then apply the
        // resolved sign to the magnitude so the result is unambiguous.
        let isOutflow = (node.amountSign ?? "").lowercased().hasPrefix("neg") || amountString.hasPrefix("-")
        let amount = isOutflow ? -abs(magnitude) : abs(magnitude)

        return ImportedTransaction(
            id: id,
            accountExternalId: node.accountId ?? accountExternalId,
            date: parseDate(node.occurredAt) ?? .now,
            merchant: describe(node),
            amount: amount,
            currencyCode: node.currency ?? "CAD"
        )
    }

    /// Best available human label for an activity, falling back to a tidied type name.
    static func describe(_ node: WealthsimpleDTO.ActivityNode) -> String {
        if let merchant = nonEmpty(node.spendMerchant) { return merchant }
        if let name = nonEmpty(node.eTransferName) { return "e-Transfer: \(name)" }
        if let originator = nonEmpty(node.aftOriginatorName) { return originator }
        if let payee = nonEmpty(node.billPayPayeeNickname) ?? nonEmpty(node.billPayCompanyName) { return "Bill payment: \(payee)" }
        if let handle = nonEmpty(node.p2pHandle) { return "Cash: \(handle)" }

        let base = node.type.map { $0.replacingOccurrences(of: "_", with: " ").capitalized } ?? "Transaction"
        return base
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    private static func dateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Queries

    /// Trimmed to the fields Ledger needs; the server accepts any valid subset of the web app's
    /// full `FetchAllAccountFinancials`.
    static let accountsQuery = """
    query FetchAccounts($identityId: ID!, $pageSize: Int = 25, $cursor: String) {
      identity(id: $identityId) {
        id
        accounts(filter: {}, first: $pageSize, after: $cursor) {
          pageInfo { hasNextPage endCursor }
          edges {
            node {
              id
              unifiedAccountType
              currency
              nickname
              status
              financials { currentCombined { netLiquidationValue { amount currency } } }
            }
          }
        }
      }
    }
    """

    static let activitiesQuery = """
    query FetchActivityFeedItems($first: Int, $cursor: Cursor, $condition: ActivityCondition, $orderBy: [ActivitiesOrderBy!] = OCCURRED_AT_DESC) {
      activityFeedItems(first: $first, after: $cursor, condition: $condition, orderBy: $orderBy) {
        edges {
          node {
            canonicalId
            accountId
            amount
            amountSign
            currency
            occurredAt
            type
            subType
            status
            spendMerchant
            eTransferName
            aftOriginatorName
            billPayCompanyName
            billPayPayeeNickname
            p2pHandle
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
    """
}
