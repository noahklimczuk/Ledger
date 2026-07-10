import Foundation
import SwiftData

@Model
final class SavingsGoal {
    var name: String
    var sfSymbolName: String
    var colorHex: String
    var targetAmount: Decimal
    /// Manually tracked contributions. Ignored while `account` is linked — the account's live
    /// balance drives progress instead.
    var currentAmount: Decimal
    var targetDate: Date?
    var isArchived: Bool
    var createdAt: Date

    /// When set, the goal tracks this account's balance instead of manual contributions —
    /// e.g. a "House Down Payment" goal pointed at the savings account the money actually
    /// lives in, so progress moves with real deposits and never needs manual upkeep.
    var account: Account?

    init(
        name: String,
        sfSymbolName: String = "target",
        colorHex: String = "#34C759",
        targetAmount: Decimal,
        currentAmount: Decimal = 0,
        targetDate: Date? = nil,
        account: Account? = nil,
        isArchived: Bool = false
    ) {
        self.name = name
        self.sfSymbolName = sfSymbolName
        self.colorHex = colorHex
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.targetDate = targetDate
        self.account = account
        self.isArchived = isArchived
        self.createdAt = .now
    }

    var isAccountTracked: Bool { account != nil }

    /// What counts toward the goal: the linked account's live balance (never below zero), or
    /// the manually tracked contributions when no account is linked.
    var savedAmount: Decimal {
        if let account { return max(account.currentBalance, 0) }
        return currentAmount
    }

    var remaining: Decimal { max(targetAmount - savedAmount, 0) }

    var isComplete: Bool { savedAmount >= targetAmount }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        let value = (savedAmount as NSDecimalNumber).doubleValue / (targetAmount as NSDecimalNumber).doubleValue
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
