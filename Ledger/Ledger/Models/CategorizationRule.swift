import Foundation
import SwiftData

/// Merchant-keyword -> category rule, matched by `CategorizationService` with token-boundary
/// rules. Created two ways: seeded as built-in defaults (`DefaultCategoryCatalog`, matchCount 0)
/// and learned automatically when the user categorizes a transaction (matchCount starts at 1 so
/// personal rules outrank same-length defaults).
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
