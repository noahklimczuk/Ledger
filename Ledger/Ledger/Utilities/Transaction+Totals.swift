import Foundation

extension Transaction {
    /// False when the transaction belongs to an archived (removed) account. An archived account is
    /// one the user chose to stop tracking, and its balance is already excluded everywhere — so its
    /// transactions must not count toward dashboard totals, budgets, reports, net worth, or
    /// recurring detection either. The Transactions tab still lists full history.
    var countsTowardTotals: Bool { account?.isArchived != true }
}
