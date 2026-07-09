import Foundation

/// DTOs matching SnapTrade's REST API JSON shapes. Field names/casing were verified against
/// docs.snaptrade.com as of writing; most fields are decoded as optionals so a schema drift
/// degrades gracefully (missing data) instead of crashing the import.
enum SnapTradeDTO {
    struct RegisterUserResponse: Decodable {
        let userId: String
        let userSecret: String
    }

    struct LoginResponse: Decodable {
        let redirectURI: String
    }

    struct Account: Decodable {
        let id: String
        let name: String?
        let number: String?
        let institutionName: String?
        let balance: Balance?

        enum CodingKeys: String, CodingKey {
            case id, name, number, balance
            case institutionName = "institution_name"
        }

        struct Balance: Decodable {
            let total: AmountCurrency?
        }

        struct AmountCurrency: Decodable {
            let amount: Decimal?
            let currency: String?
        }
    }

    struct Activity: Decodable {
        let id: String
        let type: String?
        let amount: Decimal?
        let description: String?
        let tradeDate: String?
        let settlementDate: String?
        let currency: CurrencyRef?

        enum CodingKeys: String, CodingKey {
            case id, type, amount, description, currency
            case tradeDate = "trade_date"
            case settlementDate = "settlement_date"
        }

        struct CurrencyRef: Decodable {
            let code: String?
        }
    }
}
