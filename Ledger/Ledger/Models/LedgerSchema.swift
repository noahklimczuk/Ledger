import SwiftData

enum LedgerSchema {
    static let models: [any PersistentModel.Type] = [
        Account.self,
        Transaction.self,
        SplitAllocation.self,
        Category.self,
        Budget.self,
        BudgetPeriod.self,
        Tag.self,
        CategorizationRule.self,
        RecurringSeries.self,
        SavingsGoal.self,
        BillReminder.self,
        InsightState.self,
        Debt.self
    ]
}
