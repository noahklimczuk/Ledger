import Foundation
import SwiftData

enum TransactionSourceKind: String, Codable {
    case manual
    case snapTrade
    case plaid
    case csv
    case ofx
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
    /// Stable id from the external source (e.g. SnapTrade activity id), used to dedupe re-imports. Nil for manual entries.
    var externalId: String?
    var receiptImageData: Data?

    var account: Account?
    var category: Category?

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
