import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case chequing
    case savings
    case credit
    case investment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chequing: "Chequing"
        case .savings: "Savings"
        case .credit: "Credit Card"
        case .investment: "Investment"
        }
    }

    var sfSymbolName: String {
        switch self {
        case .chequing: "banknote"
        case .savings: "banknote.fill"
        case .credit: "creditcard.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        }
    }

    /// Credit accounts accrue balance in the opposite direction: a purchase increases what's owed.
    var isLiability: Bool { self == .credit }
}

@Model
final class Account {
    var name: String
    var type: AccountType
    var institutionName: String?
    var currencyCode: String
    var startingBalance: Decimal
    var isArchived: Bool
    var createdAt: Date

    /// Non-nil when this account originated from (or is linked to) an external TransactionSource,
    /// e.g. "wealthsimple". Nil for purely manual accounts.
    var externalSourceId: String?
    var externalAccountId: String?

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction] = []

    init(
        name: String,
        type: AccountType,
        institutionName: String? = nil,
        currencyCode: String = "CAD",
        startingBalance: Decimal = 0,
        isArchived: Bool = false,
        externalSourceId: String? = nil,
        externalAccountId: String? = nil
    ) {
        self.name = name
        self.type = type
        self.institutionName = institutionName
        self.currencyCode = currencyCode
        self.startingBalance = startingBalance
        self.isArchived = isArchived
        self.createdAt = .now
        self.externalSourceId = externalSourceId
        self.externalAccountId = externalAccountId
    }

    var currentBalance: Decimal {
        startingBalance + transactions.reduce(Decimal(0)) { $0 + $1.amount }
    }

    var isLinked: Bool { externalSourceId != nil }
}
