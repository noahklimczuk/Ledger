import Foundation
import SwiftData

@Model
final class Budget {
    /// Always normalized to the first of the month (local calendar), so a Budget's
    /// identity for a given category+month is stable regardless of what day it was created.
    var month: Date
    var allocatedAmount: Decimal
    var rolloverEnabled: Bool
    var createdAt: Date

    var category: Category?

    init(month: Date, category: Category?, allocatedAmount: Decimal, rolloverEnabled: Bool = false) {
        self.month = Budget.normalize(month)
        self.category = category
        self.allocatedAmount = allocatedAmount
        self.rolloverEnabled = rolloverEnabled
        self.createdAt = .now
    }

    static func normalize(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}
