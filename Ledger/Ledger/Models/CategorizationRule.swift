import Foundation
import SwiftData

/// Merchant-keyword -> category rule. Not yet exercised by any UI in phase 1;
/// the schema exists now so the auto-categorization rule engine (later phase)
/// doesn't require a migration. Rules are meant to be created automatically
/// when a user manually overrides a transaction's category, then matched
/// against future merchant strings (substring match on `keyword`).
@Model
final class CategorizationRule {
    var keyword: String
    var matchCount: Int
    var createdAt: Date

    var category: Category?

    init(keyword: String, category: Category?, matchCount: Int = 1) {
        self.keyword = keyword.lowercased()
        self.category = category
        self.matchCount = matchCount
        self.createdAt = .now
    }
}
