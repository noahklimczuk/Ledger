import Foundation
import SwiftData

/// Per-month settings for the zero-based budget plan. One record per month (normalized to the
/// first of the month, same convention as `Budget.month`).
@Model
final class BudgetPeriod {
    var month: Date
    /// The amount the user plans to assign for the month. Nil means "use actual income received
    /// this month" — sensible for synced accounts, overridable for people who budget ahead.
    var expectedIncome: Decimal?
    var createdAt: Date

    init(month: Date, expectedIncome: Decimal? = nil) {
        self.month = Budget.normalize(month)
        self.expectedIncome = expectedIncome
        self.createdAt = .now
    }
}
