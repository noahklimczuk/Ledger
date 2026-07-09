import Foundation
import SwiftData

@Model
final class SavingsGoal {
    var name: String
    var sfSymbolName: String
    var colorHex: String
    var targetAmount: Decimal
    var currentAmount: Decimal
    var targetDate: Date?
    var isArchived: Bool
    var createdAt: Date

    init(
        name: String,
        sfSymbolName: String = "target",
        colorHex: String = "#34C759",
        targetAmount: Decimal,
        currentAmount: Decimal = 0,
        targetDate: Date? = nil,
        isArchived: Bool = false
    ) {
        self.name = name
        self.sfSymbolName = sfSymbolName
        self.colorHex = colorHex
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.targetDate = targetDate
        self.isArchived = isArchived
        self.createdAt = .now
    }

    var remaining: Decimal { max(targetAmount - currentAmount, 0) }

    var isComplete: Bool { currentAmount >= targetAmount }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        let value = (currentAmount as NSDecimalNumber).doubleValue / (targetAmount as NSDecimalNumber).doubleValue
        return min(max(value, 0), 1)
    }

    /// Contribution per month needed to hit the target by `targetDate`, or nil if no date/overdue.
    var requiredMonthlyContribution: Decimal? {
        guard let targetDate, !isComplete else { return nil }
        let months = Calendar.current.dateComponents([.month], from: .now, to: targetDate).month ?? 0
        guard months > 0 else { return nil }
        return remaining / Decimal(months)
    }
}
