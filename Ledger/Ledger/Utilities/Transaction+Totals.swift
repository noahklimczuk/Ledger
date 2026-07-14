import Foundation

// nonisolated so the off-main sync pipeline (RecurringDetectionService) can read these derived
// flags — the project defaults types (and their extensions) to @MainActor.
nonisolated extension Transaction {
    /// False when the transaction belongs to an archived (removed) account. An archived account is
    /// one the user chose to stop tracking, and its balance is already excluded everywhere — so its
    /// transactions must not count toward dashboard totals, budgets, reports, net worth, or
    /// recurring detection either. The Transactions tab still lists full history.
    var countsTowardTotals: Bool { account?.isArchived != true }

    /// True when this transaction is a transfer between the user's own accounts (its category is
    /// marked as a transfer). Transfers move money without being income or spending, so they're
    /// excluded from income/expense/spending totals — but still affect account balances and net
    /// worth, where the two sides of the transfer cancel out.
    var isTransfer: Bool { category?.isTransfer == true }
}
