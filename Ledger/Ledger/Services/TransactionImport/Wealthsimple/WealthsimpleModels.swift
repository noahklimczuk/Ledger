import Foundation

/// DTOs for the slice of Wealthsimple's API this app uses. Everything decodes defensively
/// (optional fields, `convertFromSnakeCase` for the snake_case OAuth endpoints -- a no-op on the
/// already-camelCase GraphQL payloads) so a response-shape change degrades to missing data rather
/// than a crash.
///
/// These follow the shapes used by the community `ws-api` clients (reverse-engineered from the
/// Wealthsimple web app); field names may need small fixes once seen against a live account.
enum WealthsimpleDTO {
    // MARK: - OAuth

    /// `POST /oauth/v2/token` (password grant and refresh grant).
    struct TokenResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        /// Present on failure, e.g. `invalid_grant` (which, with no OTP supplied, means 2FA is
        /// required rather than that the password was wrong).
        let error: String?
    }

    /// `GET /oauth/v2/token/info` -- carries the identity the tokens belong to.
    struct TokenInfoResponse: Decodable {
        let identityCanonicalId: String?
    }

    // MARK: - GraphQL envelope

    struct GraphQLResponse<T: Decodable>: Decodable {
        let data: T?
        let errors: [GraphQLError]?
    }

    struct GraphQLError: Decodable {
        let message: String?
    }

    struct PageInfo: Decodable {
        let hasNextPage: Bool?
        let endCursor: String?
    }

    // MARK: - Accounts (FetchAllAccountFinancials, trimmed)

    struct AccountsData: Decodable {
        let identity: Identity?

        struct Identity: Decodable {
            let accounts: Accounts?
        }

        struct Accounts: Decodable {
            let pageInfo: PageInfo?
            let edges: [Edge]?
        }

        struct Edge: Decodable {
            let node: AccountNode?
        }
    }

    struct AccountNode: Decodable {
        let id: String?
        /// e.g. `CASH`, `SELF_DIRECTED_TFSA`, `CREDIT_CARD`.
        let unifiedAccountType: String?
        let currency: String?
        let nickname: String?
        /// `open`, `closed`, ...
        let status: String?
        let financials: Financials?

        struct Financials: Decodable {
            let currentCombined: CurrentCombined?
        }

        struct CurrentCombined: Decodable {
            let netLiquidationValue: Money?
        }
    }

    struct Money: Decodable {
        let amount: String?
        let currency: String?
    }

    // MARK: - Activities (FetchActivityFeedItems, trimmed)

    struct ActivitiesData: Decodable {
        let activityFeedItems: ActivityFeedItems?

        struct ActivityFeedItems: Decodable {
            let pageInfo: PageInfo?
            let edges: [Edge]?
        }

        struct Edge: Decodable {
            let node: ActivityNode?
        }
    }

    /// One row of the Cash account activity feed. `amount` is a positive decimal string; the
    /// direction lives in `amountSign` (`positive` = money in, `negative` = money out), which
    /// already matches Ledger's own sign convention.
    struct ActivityNode: Decodable {
        let canonicalId: String?
        let accountId: String?
        let amount: String?
        let amountSign: String?
        let currency: String?
        let occurredAt: String?
        let type: String?
        let subType: String?
        let status: String?

        // Fields used only to build a human-readable description.
        let spendMerchant: String?
        let eTransferName: String?
        let aftOriginatorName: String?
        let billPayCompanyName: String?
        let billPayPayeeNickname: String?
        let p2pHandle: String?
    }
}
