import Foundation

enum SafeToSpendCalculator {
    /// income - committed bills - budget allocations - goal contributions.
    /// `committedBills` and `goalContributions` default to 0 in phase 1 since recurring-bill
    /// detection and savings goals don't exist yet in the data model; wire real values in once
    /// those features land instead of changing this signature's meaning.
    static func calculate(
        income: Decimal,
        budgetAllocations: Decimal,
        committedBills: Decimal = 0,
        goalContributions: Decimal = 0
    ) -> Decimal {
        income - committedBills - budgetAllocations - goalContributions
    }
}
