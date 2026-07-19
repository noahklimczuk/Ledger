import Foundation
import SwiftData

/// Merchant-keyword → debt rule, the debt-tracker counterpart to `CategorizationRule`. Learned
/// automatically the first time the user assigns a transaction to a debt, then replayed by
/// `DebtAssignmentService` onto future and imported transactions with the same token-boundary
/// matching categorization uses — so once "Visa Payment" is filed under the Visa debt, every later
/// Visa payment files itself.
@Model
final class DebtRule {
    var keyword: String
    /// Bumped each time the rule matches; ties in `bestRule` break toward the more-used rule.
    var matchCount: Int
    var createdAt: Date

    var debt: Debt?

    init(keyword: String, debt: Debt?, matchCount: Int = 1) {
        self.keyword = keyword.lowercased()
        self.debt = debt
        self.matchCount = matchCount
        self.createdAt = .now
    }
}
