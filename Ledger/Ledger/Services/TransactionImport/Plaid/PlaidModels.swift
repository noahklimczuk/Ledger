import Foundation

/// DTOs for the subset of the Plaid REST API this app uses. Everything is decoded defensively
/// (optional fields, snake_case → camelCase via `convertFromSnakeCase`) so a response-shape
/// mismatch degrades to missing data rather than a crash. Field names/paths follow
/// https://plaid.com/docs/api -- reconfirm against live responses once real keys are available.
enum PlaidDTO {
    // MARK: link/token/create

    struct LinkTokenCreateResponse: Decodable {
        let linkToken: String?
        let hostedLinkUrl: String?
        let expiration: String?
    }

    // MARK: link/token/get (Hosted Link result retrieval)

    struct LinkTokenGetResponse: Decodable {
        let linkToken: String?
        let linkSessions: [LinkSession]?

        struct LinkSession: Decodable {
            let linkSessionId: String?
            let results: Results?
        }

        struct Results: Decodable {
            let itemAddResults: [ItemAddResult]?
        }

        struct ItemAddResult: Decodable {
            let publicToken: String?
            let institution: Institution?
        }

        struct Institution: Decodable {
            let name: String?
            let institutionId: String?
        }

        /// First public token across all sessions/items, if the user completed a connection.
        var firstPublicToken: String? {
            linkSessions?
                .compactMap { $0.results?.itemAddResults }
                .flatMap { $0 }
                .compactMap { $0.publicToken }
                .first
        }

        var firstInstitutionName: String? {
            linkSessions?
                .compactMap { $0.results?.itemAddResults }
                .flatMap { $0 }
                .compactMap { $0.institution?.name }
                .first
        }
    }

    // MARK: item/public_token/exchange

    struct ExchangeResponse: Decodable {
        let accessToken: String?
        let itemId: String?
    }

    // MARK: accounts/balance/get

    struct AccountsResponse: Decodable {
        let accounts: [Account]?
        let item: Item?
    }

    struct Item: Decodable {
        let itemId: String?
        let institutionId: String?
    }

    struct Account: Decodable {
        let accountId: String
        let name: String?
        let officialName: String?
        let type: String?
        let subtype: String?
        let balances: Balances?

        struct Balances: Decodable {
            let available: Decimal?
            let current: Decimal?
            let isoCurrencyCode: String?
        }
    }

    // MARK: transactions/get

    struct TransactionsResponse: Decodable {
        let accounts: [Account]?
        let transactions: [Transaction]?
        let totalTransactions: Int?
    }

    struct Transaction: Decodable {
        let transactionId: String
        let accountId: String?
        /// Plaid convention: **positive** = money out of the account, **negative** = money in.
        let amount: Decimal?
        let date: String?
        let authorizedDate: String?
        let name: String?
        let merchantName: String?
        let isoCurrencyCode: String?
        let pending: Bool?
    }

    // MARK: transactions/refresh

    struct RefreshResponse: Decodable {
        let requestId: String?
    }

    // MARK: error envelope

    struct ErrorResponse: Decodable {
        let errorType: String?
        let errorCode: String?
        let errorMessage: String?
        let displayMessage: String?
    }
}
