import Foundation
import SwiftData

enum TransactionSourceKind: String, Codable {
    case manual
    case wealthsimple
    case csv
    case ofx

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .wealthsimple: return "Wealthsimple"
        case .csv: return "CSV Import"
        case .ofx: return "OFX Import"
        }
    }
}

@Model
final class Transaction {
    var date: Date
    var merchant: String
    /// Signed amount in the account's currency: negative = money out, positive = money in.
    var amount: Decimal
    var notes: String?
    var isReviewed: Bool
    var createdAt: Date

    var sourceKind: TransactionSourceKind
    /// Stable id from the external source (e.g. Wealthsimple activity id), used to dedupe re-imports. Nil for manual entries.
    var externalId: String?
    var receiptImageData: Data?

    var account: Account?
    var category: Category?
    /// The debt this transaction is assigned to, if any. Assigning a *new* transaction to a debt
    /// applies its amount to the debt's balance once, at creation (see `TransactionEditViewModel`);
    /// linking an existing transaction only records the association and never moves the balance.
    var debt: Debt?

    @Relationship(deleteRule: .cascade, inverse: \SplitAllocation.transaction)
    var splits: [SplitAllocation] = []

    var tags: [Tag] = []

    init(
        date: Date,
        merchant: String,
        amount: Decimal,
        account: Account?,
        category: Category? = nil,
        notes: String? = nil,
        isReviewed: Bool = false,
        sourceKind: TransactionSourceKind = .manual,
        externalId: String? = nil
    ) {
        self.date = date
        self.merchant = merchant
        self.amount = amount
        self.account = account
        self.category = category
        self.notes = notes
        self.isReviewed = isReviewed
        self.sourceKind = sourceKind
        self.externalId = externalId
        self.createdAt = .now
    }

    var isSplit: Bool { !splits.isEmpty }

    /// Sum of split allocations, for validating they add up to `amount`.
    var splitTotal: Decimal {
        splits.reduce(Decimal(0)) { $0 + $1.amount }
    }
}
